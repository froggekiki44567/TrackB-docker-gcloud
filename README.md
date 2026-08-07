# Track B — gcloud + Docker Compose on a GCE VM

A tiny Flask "hello world" app, deployed onto a Google Compute Engine VM
using nothing but a bash script and `gcloud`. Two environments — `dev`
and `prod` — run from the exact same script and the exact same app code.
Only a config file changes between them.

**Live right now:** `dev` is up and serving traffic at
`http://34.78.153.254/health`


**Project:** `cand-a2-202608` · **Region:** `europe-west1` (locked)

| | **dev** — applied | **prod** — dry-run only |
|---|---|---|
| VPC | `dev-vpc` (custom-mode) | same script, plan only |
| Subnet | `dev-subnet` — `10.10.0.0/24` | — |
| VM | `dev-vm` · `e2-medium` · public IP | `prod-vm` · `e2-standard-4` · no public IP (never created) |
| Port 80 (HTTP) | open to `0.0.0.0/0` | firewall rule never created |
| Port 22 (SSH) | open to `0.0.0.0/0` | open to `0.0.0.0/0` |
| App | `docker compose up` via startup-script | — |

SSH is the one rule identical across both environments.

---

## Which track, and why

Track B. I'm stronger day-to-day on Linux, Docker and scripting than on
Terraform or Kubernetes. I've touched Terraform for small things and
read into Kubernetes, but neither is something I'd confidently build
and explain live under time pressure. Track B is what I'd genuinely
reach for first to get something running quickly, so it's also the
track that shows my actual working style rather than me improvising
tools I'm still learning. It was also genuinely interesting to getting
build the whole thing to provision itself end-to-end, rather than
just describing what it would do, was the most satisfying part.

---

## How to run it

You're given an existing GCP project (`cand-a2-202608`), not an empty
one, so "starting from empty" here means: someone else clones this
repo, has never touched this project before, and runs the following.

### Clone this repo

```bash
git clone https://github.com/froggekiki44567/TrackB-docker-gcloud.git
cd TrackB-docker-gcloud
```

### Install the gcloud CLI (if you don't have it)

***macOS** (Homebrew):
```bash
brew install --cask google-cloud-sdk
```

**macOS / Linux** (official installer):
```bash
curl https://sdk.cloud.google.com | bash
```

**Windows** (winget, if available):
```powershell
winget install --id Google.CloudSDK
```

**Windows** (installer, if no winget):
```powershell
(New-Object Net.WebClient).DownloadFile("https://dl.google.com/dl/cloudsdk/channels/rapid/GoogleCloudSDKInstaller.exe", "$env:Temp\GoogleCloudSDKInstaller.exe")
& $env:Temp\GoogleCloudSDKInstaller.exe
```

Verify it worked (any OS):
```bash
gcloud --version
```

### 0. One-time GCP setup

```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project cand-a2-202608
gcloud services enable compute.googleapis.com
```

Two login commands are both required as the brief asks for both. Only
the first is actually used by this track's script (it calls the
`gcloud` CLI directly), but the second sets up Application Default
Credentials as requested regardless of track.

Once gcloud is installed, the rest of this README (`chmod`, `grep`,
`curl`, etc.) assumes a Unix-like shell. On Windows, run everything
after this point in **Git Bash** (installed alongside Git for Windows)
or **WSL** — not PowerShell or Command Prompt, which don't have these
commands built in.

Sanity-check before doing anything:

```bash
gcloud compute regions describe europe-west1 --project=cand-a2-202608 --format=json \
  | grep -B1 -A2 '"metric": "CPUS"'
```

Should show `limit: 12.0`, `usage: 0.0` on a fresh project.

### 1. Point `deploy.sh` at this repo

Already done in this submission: `scripts/deploy.sh` clones
`https://github.com/froggekiki44567/TrackB-docker-gcloud`. If you fork
this, update that URL and push before provisioning, since the VM clones
it during boot.

### 2. Make the scripts runnable

```bash
chmod +x scripts/*.sh
```

### 3. Provision `dev` — dry-run first, then for real

```bash
cd scripts
./provision.sh dev              # prints what would happen, creates nothing
./provision.sh dev --apply      # actually creates it
```

Dry-run is the default on purpose, because `--apply` has to be typed
deliberately. Wait 3-5 minutes after `--apply` finishes: the VM itself
comes up in seconds, but Docker installation, the git clone, and the
image build all happen afterward, inside the VM's startup script, in
the background.

### 4. Verify

```bash
gcloud compute instances list --project=cand-a2-202608
# copy the EXTERNAL_IP, then:
curl http://<EXTERNAL_IP>/health
curl http://<EXTERNAL_IP>/
```

If nothing answers after 5 minutes, check what actually happened during
boot before assuming something's broken:

```bash
gcloud compute ssh dev-vm --zone=europe-west1-b --project=cand-a2-202608 \
  --command="sudo journalctl -u google-startup-scripts.service --no-pager | tail -60"
```

### 5. `prod` — dry-run only

```bash
./provision.sh prod
```

Never applied in this submission. Prints the plan where is a bigger machine,
and crucially no `--apply` is ever passed, so nothing is created.

### 6. Tear down

```bash
./teardown.sh dev
```

Removes the VM, both firewall rules, the subnet, and the network, in
that dependency order.

---

## Evidence it works

`evidence/dev-curl-output.txt` captured with `curl` directly and also screenshots in addition

![alt text](<evidence/Screenshot 2026-08-07 at 23.10.14.png>)
![alt text](<evidence/Screenshot 2026-08-07 at 23.10.32.png>)

### Evidence for rerun

![alt text](<evidence/Screenshot 2026-08-08 at 00.00.31.png>)
---

## What differs between dev and prod

| | dev | prod |
|---|---|---|
| Machine type | `e2-medium` (2 vCPU) | `e2-standard-4` (4 vCPU) |
| Public IP | yes | no (`--no-address`) |
| Port 80 | open to `0.0.0.0/0` | firewall rule never created — closed |
| Applied in this submission | yes | no — dry-run/plan only |

Both share: the same VPC creation logic, the same subnet CIDR pattern,
the same startup script, the same `docker-compose.yml`, and the same
SSH firewall rule (port 22 open in both — you always need a way in to
debug or demo the box; this is the only ingress rule that's identical
across environments rather than differing).

vCPU usage: only `dev` is ever created (2 vCPU used), well under the
12 vCPU quota. `prod` (4 vCPU) is never applied.

---

## How the pieces actually work

**Custom-mode VPC.** Required by the project's region lock — an
auto-mode VPC tries to create a subnet in every GCP region and fails
against a region-locked project. Custom-mode means the script defines
exactly one subnet, in `europe-west1`, and nothing else.

**No firewall rules exist by default.** Custom-mode VPCs start with
zero ingress rules — not even SSH. `provision.sh` explicitly opens port
22 (both environments) and port 80 (dev only).

**The environment name reaches the app via GCE instance metadata**, not
a file baked into the image. `provision.sh` sets
`--metadata=environment=dev` (or `prod`) on the VM. `deploy.sh` reads it
back with:

```bash
curl -s -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/attributes/environment"
```

`metadata.google.internal` is a special address only the VM itself can
reach.

**"Starts when the machine boots" is satisfied by GCE's own behavior**,
not a separate systemd unit: `--metadata-from-file=startup-script=deploy.sh`
means GCP re-runs `deploy.sh` on every boot, not just the first — so a
reboot re-installs Docker (near-instant if already installed), re-pulls
the repo, and re-runs `docker compose up -d --build`.

**Docker is pinned, with a fallback.** `deploy.sh` targets a specific
Docker version and checks `apt-cache madison docker-ce` before
installing it. If that exact build has aged out of the repo by the time
this actually runs, it falls back to the current stable release —
logged clearly either way, rather than the whole deploy failing on a
stale pin.

---

## Assumptions

The brief says: if something's ambiguous, make a call, write it down,
move on. Here's what I decided:

- **SSH open to `0.0.0.0/0`, not restricted to one IP.** The brief
  doesn't ask for it to be narrower, and cost/blast-radius isn't a
  grading concern per the ground rules. I'd tighten this — either to a
  specific IP range or IAP tunneling — for anything longer-lived than a
  take-home.
- **The app has two routes (`/`, `/health`), not exactly the "twelve
  lines" example.** I kept two small routes
  rather than stripping to the bare minimum, mainly so there was
  something real for a health check to hit.
- **`gs://cand-a2-202608-tfstate` is unused.** Provided "if your track
  needs it" — Track B has no Terraform state to keep, so it plays no
  role here.
- **Docker's exact version is pinned with an automatic fallback**
  rather than either a hard pin (which risks breaking if that build
  ages out of the repo) or no pin at all (which the grading criteria
  flags against). This felt like the right trade-off for a script that
  needs to still work correctly months from now.
- **prod gets `--no-address` in addition to the missing firewall
  rule** — two independent layers (no public IP, and no open port)
  rather than relying on the firewall alone to make prod unreachable.

---

## What I'd change before this went anywhere near real production

The app image gets built directly on the VM from a freshly cloned repo
on every boot, which is fine for a demo but not something I'd want
long-term. I'd build the image in CI, push it to Artifact Registry,
and have the VM (or more realistically a load-balanced managed instance
group, or Cloud Run at that point) just pull a tagged image instead of
holding a git checkout and a build toolchain on every machine. I'd also
restrict the SSH firewall rule to a specific IP range or switch to IAP
tunneling instead of leaving port 22 open to the whole internet.
And any real secrets such as: API keys, DB credentials I 
would need to move out of GCE metadata into Secret Manager, since
metadata is unencrypted and readable by anything with access to the
VM; the environment name being in metadata is fine because it isn't
sensitive, but it's not the right pattern for anything that is.

---

## What I didn't finish, or didn't fully understand

`provision.sh` was the hardest part of this whole exercise to get
right and getting a single script to be safely re-runnable, parameterised
per environment, and readable all at once took more iteration than I
expected. The idempotency pattern I ended up with
(`2>/dev/null || echo "... exists, skipping"`) works, and I tested it, can be seen
above, where every resource correctly reports
"exists, skipping" instead of failing or duplicating anything. But I'll
be honest that it's not a fully correct pattern: it swallows *any*
error from `gcloud`, not just "resource already exists", but a real
failure (bad permissions, a quota issue, a typo in a flag) would print
the same "skipping" message and let the script carry on as if nothing
was wrong. A more correct version would check resource state first
(e.g. `gcloud ... describe`) and only skip on an actual already-exists
condition. I understood the trade-off only after reading a forum thread
about `set -e` and silent error handling in bash scripts, which is
when it clicked that `2>/dev/null || echo ...` hides real failures,
not just "already exists" ones.
---

## Resources used

- **Claude** — used throughout for drafting main
  logic and structuring this README. I wrote and re-wrote the bash myself,
  Claude was closer to a rubber duck with working knowledge of `gcloud` flags than an autocomplete.
- [GCP: Storing and retrieving instance metadata](https://cloud.google.com/compute/docs/metadata/overview) —
  official docs on `--metadata` / `--metadata-from-file`, and the
  reserved `startup-script` key that GCE re-runs on every boot.
- [Docker: Compose file reference](https://docs.docker.com/reference/compose-file/) —
  the official Compose Specification, used to write `docker-compose.yml`
  itself (service definition, ports, restart policy).
- [How to Install a Specific Version of Docker Engine on Ubuntu](https://oneuptime.com/blog/post/2026-02-08-how-to-install-a-specific-version-of-docker-engine-on-ubuntu/view) —
  the `apt-cache madison docker-ce` pattern in `deploy.sh` for checking
  a pinned version exists before installing it, with a fallback to
  latest stable if it's aged out of the repo.
- [Idempotent AWS Resource Creation — with tools you have laying around the house](https://blog.tbcdevelopmentgroup.com/2026-03-20-post.html) —
  this is what made the `2>/dev/null || echo "exists, skipping"` gap
  click for me: silently swallowing errors is how idempotency bugs are
  born, since it catches *any* failure, not specifically "already
  exists."
- [Shell scripts: Perils of "set -e" for error handling](https://david.rothlis.net/shell-set-e/) —
  background on why `set -e` alone doesn't catch everything, and why
  commands before `||` are exempt from it.
