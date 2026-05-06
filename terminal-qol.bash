#!/usr/bin/env bash
# =============================================================================
# terminal-qol.bash — Quality-of-Life Shell Enhancements
# Version: 1.1.0
# Source from ~/.bashrc: [ -f "$HOME/.config/qol/terminal-qol.bash" ] && source "$HOME/.config/qol/terminal-qol.bash"
# =============================================================================

# =============================================================================
# SECTION 1: GUARD — Interactive check & idempotency
# =============================================================================

# Only run in interactive shells
[[ $- != *i* ]] && return 0

# Idempotency guard: prevent double-sourcing side effects
# (safe to re-source for function redefinition, but skip setup blocks)
if [[ -z "${__QOL_LOADED:-}" ]]; then
    __QOL_LOADED=1
    __QOL_FIRST_LOAD=1
    __QOL_LOAD_TIME_START="${EPOCHREALTIME:-0}"
else
    __QOL_FIRST_LOAD=0
fi

# Bash version check (require Bash 4+)
if (( BASH_VERSINFO[0] < 4 )); then
    echo "[qol] Warning: Bash ${BASH_VERSION} detected. Some features require Bash 4+. Upgrade recommended." >&2
fi

# =============================================================================
# SECTION 2: CONFIGURATION DEFAULTS
# Users may set these before sourcing to customize behavior.
# =============================================================================

# Feature toggles (1=enabled, 0=disabled)
: "${QOL_WARN_MISSING:=1}"       # Warn about missing optional tools
: "${QOL_ENABLE_GIT:=1}"         # Git aliases and functions
: "${QOL_ENABLE_DOCKER:=1}"      # Docker helpers
: "${QOL_ENABLE_K8S:=1}"         # Kubernetes helpers
: "${QOL_ENABLE_PROMPT:=1}"      # Custom prompt (skipped if starship detected)
: "${QOL_SAFE_ALIASES:=1}"       # Safety aliases for rm/cp/mv
: "${QOL_ENABLE_NODE:=1}"        # Node/npm helpers
: "${QOL_ENABLE_PYTHON:=1}"      # Python helpers
: "${QOL_ENABLE_RUST:=1}"        # Rust/cargo helpers
: "${QOL_ENABLE_FZF:=1}"         # fzf integrations
: "${QOL_ENABLE_DIRENV:=1}"      # direnv integration
: "${QOL_ENABLE_ZOXIDE:=1}"      # zoxide integration
: "${QOL_ENABLE_GH:=1}"          # GitHub CLI helpers
: "${QOL_ENABLE_TMUX:=1}"        # tmux helpers
: "${QOL_ENABLE_PODMAN:=1}"      # Podman helpers
: "${QOL_PROMPT_STYLE:=minimal}" # Prompt style: minimal | powerline | emoji

# Internal state
declare -A __QOL_WARNED=()       # Tracks which warnings have been shown
declare -A __QOL_FEATURES=()     # Tracks which features are active

# =============================================================================
# SECTION 3: LOGGING HELPERS
# =============================================================================

# __qol_info: Print informational message (prefixed)
__qol_info() {
    echo "[qol] $*" >&2
}

# __qol_warn: Print a warning, but only once per session per key
# Usage: __qol_warn <unique_key> <message>
__qol_warn() {
    local key="$1"
    shift
    if [[ "${QOL_WARN_MISSING}" == "1" && -z "${__QOL_WARNED[$key]:-}" ]]; then
        echo "[qol] ⚠  $*" >&2
        __QOL_WARNED["$key"]=1
    fi
}

# __qol_debug: Only prints when QOL_DEBUG=1
__qol_debug() {
    [[ "${QOL_DEBUG:-0}" == "1" ]] && echo "[qol:debug] $*" >&2
}

# =============================================================================
# SECTION 4: DEPENDENCY HELPERS
# =============================================================================

# has_cmd: Returns 0 if command exists on PATH, 1 otherwise
# Usage: has_cmd git
has_cmd() {
    command -v "$1" &>/dev/null
}

# require_cmd: Prints a warning and returns 1 if command is missing
# Usage: require_cmd jq "JSON parsing" || return 1
require_cmd() {
    local cmd="$1"
    local feature="${2:-$cmd}"
    if ! has_cmd "$cmd"; then
        __qol_warn "require_${cmd}" "Feature '${feature}' requires '${cmd}' (not found). Install it to enable this feature."
        return 1
    fi
    return 0
}

# __qol_feature: Register a feature as active
__qol_feature() {
    __QOL_FEATURES["$1"]="${2:-enabled}"
}

# =============================================================================
# SECTION 5: PATH HELPERS
# =============================================================================

# path: Print each PATH entry on its own line
path() {
    tr ':' '\n' <<< "$PATH"
}

# path_add: Safely prepend a directory to PATH (no duplicates)
# Usage: path_add ~/bin
path_add() {
    local dir
    dir="$(realpath -m "$1" 2>/dev/null || echo "$1")"
    if [[ -d "$dir" ]] && [[ ":$PATH:" != *":$dir:"* ]]; then
        export PATH="$dir:$PATH"
        __qol_debug "Added to PATH: $dir"
    fi
}

# path_add_back: Safely append a directory to PATH (no duplicates)
path_add_back() {
    local dir
    dir="$(realpath -m "$1" 2>/dev/null || echo "$1")"
    if [[ -d "$dir" ]] && [[ ":$PATH:" != *":$dir:"* ]]; then
        export PATH="$PATH:$dir"
        __qol_debug "Appended to PATH: $dir"
    fi
}

# path_rm: Remove one or more directories from PATH
# Usage: path_rm ~/.local/bin /tmp/bin
path_rm() {
    local remove dir new_path=""
    IFS=':' read -r -a __qol_path_parts <<< "$PATH"
    for dir in "${__qol_path_parts[@]}"; do
        local keep=1
        for remove in "$@"; do
            remove="$(realpath -m "$remove" 2>/dev/null || echo "$remove")"
            [[ "$dir" == "$remove" ]] && keep=0 && break
        done
        (( keep )) && new_path="${new_path:+${new_path}:}${dir}"
    done
    unset __qol_path_parts
    export PATH="$new_path"
}

# path_dedupe: Remove duplicate PATH entries while preserving first occurrence
path_dedupe() {
    local dir new_path="" seen=":"
    IFS=':' read -r -a __qol_path_parts <<< "$PATH"
    for dir in "${__qol_path_parts[@]}"; do
        [[ -z "$dir" ]] && continue
        if [[ "$seen" != *":$dir:"* ]]; then
            seen+="$dir:"
            new_path="${new_path:+${new_path}:}${dir}"
        fi
    done
    unset __qol_path_parts
    export PATH="$new_path"
}

# =============================================================================
# SECTION 6: ALIASES — Shell UX
# =============================================================================

# --- ls / directory listing ---
if has_cmd eza; then
    alias ls='eza --group-directories-first'
    alias ll='eza -lah --group-directories-first --git'
    alias lt='eza --tree --level=2 --group-directories-first'
    alias l='eza -lh --group-directories-first'
    __qol_feature "ls" "eza"
elif has_cmd exa; then
    alias ls='exa --group-directories-first'
    alias ll='exa -lah --group-directories-first --git'
    alias lt='exa --tree --level=2'
    alias l='exa -lh --group-directories-first'
    __qol_feature "ls" "exa"
else
    # Detect whether ls supports --color
    if command ls --color=auto &>/dev/null 2>&1; then
        alias ls='ls --color=auto --group-directories-first 2>/dev/null || ls --color=auto'
    else
        alias ls='ls -G'  # macOS
    fi
    alias ll='ls -lAh'
    alias l='ls -lh'
    __qol_feature "ls" "coreutils"
fi

# --- cat / paging ---
if has_cmd bat; then
    alias cat='bat --paging=never'
    alias batl='bat --paging=always'
    __qol_feature "cat" "bat"
elif has_cmd batcat; then
    # Debian/Ubuntu package name
    alias cat='batcat --paging=never'
    alias batl='batcat --paging=always'
    __qol_feature "cat" "batcat"
else
    __qol_warn "bat" "Install 'bat' for syntax-highlighted file viewing (cat replacement)."
fi

# --- grep ---
if has_cmd rg; then
    alias grep='rg --color=auto'
    alias rgrep='rg'
    __qol_feature "grep" "ripgrep"
else
    alias grep='grep --color=auto'
    alias egrep='grep -E --color=auto'
    alias fgrep='grep -F --color=auto'
    __qol_warn "rg" "Install 'ripgrep' (rg) for faster, smarter grep."
    __qol_feature "grep" "grep"
fi

# --- diff ---
if has_cmd delta; then
    alias diff='delta'
    __qol_feature "diff" "delta"
elif has_cmd colordiff; then
    alias diff='colordiff'
    __qol_feature "diff" "colordiff"
else
    alias diff='diff --color=auto 2>/dev/null || diff'
    __qol_feature "diff" "diff"
fi

# --- find ---
if has_cmd fd; then
    alias find='fd'
    __qol_feature "find" "fd"
else
    __qol_warn "fd" "Install 'fd' for a faster, friendlier 'find' alternative."
    __qol_feature "find" "find"
fi

# --- Safe aliases ---
if [[ "${QOL_SAFE_ALIASES}" == "1" ]]; then
    alias rm='rm -i'
    alias cp='cp -i'
    alias mv='mv -i'
    alias ln='ln -i'
    __qol_feature "safe_aliases" "enabled"
fi

# --- Navigation ---
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias -- -='cd -'
alias ~='cd ~'

# --- Misc quality of life ---
alias reload_shell='source ~/.bashrc && echo "[qol] Shell reloaded."'
alias path='path'  # noop, function already defined
alias c='clear'
alias h='history'
alias j='jobs -l'
alias df='df -h'
alias du='du -h'
alias free='free -h 2>/dev/null || vm_stat'  # vm_stat fallback for macOS
alias mkdir='mkdir -pv'
alias wget='wget -c'  # resume downloads by default

# sudo helpers
alias please='sudo $(fc -ln -1)'
alias sudo_last='sudo $(fc -ln -1)'

# =============================================================================
# SECTION 7: CORE FUNCTIONS
# =============================================================================

# mkcd: Make directory (including parents) and cd into it
mkcd() {
    if [[ -z "$1" ]]; then
        echo "Usage: mkcd <directory>" >&2
        return 1
    fi
    mkdir -p "$1" && cd "$1" || return 1
}

# up: Move up N directories
# Usage: up 3
up() {
    local n="${1:-1}"
    local target=""
    if ! [[ "$n" =~ ^[0-9]+$ ]]; then
        echo "Usage: up <N>" >&2
        return 1
    fi
    for (( i=0; i<n; i++ )); do
        target+="../"
    done
    cd "$target" || return 1
}

# extract: Universal archive extraction
# Usage: extract archive.tar.gz [archive2.zip ...]
extract() {
    if [[ "$#" -eq 0 ]]; then
        echo "Usage: extract <archive> [archive2 ...]" >&2
        return 1
    fi

    local file status=0
    for file in "$@"; do
        if [[ ! -f "$file" ]]; then
            echo "[qol] File not found: $file" >&2
            status=1
            continue
        fi

        case "$file" in
            *.tar.bz2)   tar xjf "$file"    ;;
            *.tar.gz)    tar xzf "$file"    ;;
            *.tar.xz)    tar xJf "$file"    ;;
            *.tar.zst)   tar --zstd -xf "$file" 2>/dev/null || { require_cmd zstd "tar.zst extraction" && zstd -d "$file" -o "${file%.zst}" && tar xf "${file%.zst}"; } ;;
            *.tar)       tar xf "$file"     ;;
            *.tbz2)      tar xjf "$file"    ;;
            *.tgz)       tar xzf "$file"    ;;
            *.bz2)       bunzip2 "$file"    ;;
            *.gz)        gunzip "$file"     ;;
            *.xz)        unxz "$file"       ;;
            *.zst)       require_cmd zstd "zstd decompression" && zstd -d "$file" ;;
            *.zip)       unzip "$file"      ;;
            *.Z)         uncompress "$file" ;;
            *.7z)        require_cmd 7z "7-zip extraction" && 7z x "$file" ;;
            *.rar)       require_cmd unrar "rar extraction" && unrar x "$file" ;;
            *.deb)       require_cmd dpkg "deb extraction" && dpkg -x "$file" "${file%.deb}" ;;
            *)
                echo "[qol] Unknown archive format: $file" >&2
                status=1
                ;;
        esac || status=1
    done
    return "$status"
}

# serve: Start a local HTTP server in the current directory
# Usage: serve [port] [host]
serve() {
    local port="${1:-8080}"
    local host="${2:-localhost}"
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        echo "Usage: serve [port] [host]" >&2
        return 1
    fi
    echo "[qol] Serving $(pwd) at http://${host}:${port} — press Ctrl+C to stop"

    if has_cmd python3; then
        python3 -m http.server "$port" --bind "$host"
    elif has_cmd python; then
        # Python 2 fallback
        python -m SimpleHTTPServer "$port"
    elif has_cmd ruby; then
        ruby -run -e httpd . -p "$port"
    elif has_cmd npx; then
        npx --yes serve -l "$port" .
    else
        echo "[qol] No suitable HTTP server found. Install python3, ruby, or npx." >&2
        return 1
    fi
}

# ports: List listening ports
ports() {
    if has_cmd ss; then
        ss -tulnp
    elif has_cmd netstat; then
        netstat -tulnp 2>/dev/null || netstat -an | command grep LISTEN
    elif has_cmd lsof; then
        lsof -iTCP -sTCP:LISTEN -n -P
    else
        echo "[qol] No suitable tool found (ss, netstat, lsof)." >&2
        return 1
    fi
}

# port_kill: Kill whatever is listening on a given port
# Usage: port_kill 3000
port_kill() {
    if [[ -z "$1" ]]; then
        echo "Usage: port_kill <port>" >&2
        return 1
    fi
    local port="$1"
    local pids
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        echo "Usage: port_kill <port>" >&2
        return 1
    fi

    if has_cmd lsof; then
        pids=$(lsof -ti "TCP:${port}" -sTCP:LISTEN 2>/dev/null)
    elif has_cmd fuser; then
        pids=$(fuser "${port}/tcp" 2>/dev/null)
    else
        echo "[qol] Cannot find process on port ${port}: install lsof or fuser." >&2
        return 1
    fi

    if [[ -z "$pids" ]]; then
        echo "[qol] Nothing listening on port ${port}."
        return 0
    fi

    echo "[qol] Killing PIDs: $pids (port ${port})"
    # xargs -r to avoid killing nothing
    echo "$pids" | xargs -r kill -9
}

# psg: Search running processes by command line
# Usage: psg postgres
psg() {
    [[ -z "$1" ]] && { echo "Usage: psg <pattern>" >&2; return 1; }
    ps aux | command grep -i -- "$1" | command grep -v '[g]rep'
}

# envload / dotenv: Load .env file into the current shell, safely
# Skips comments and blank lines; does NOT execute arbitrary code.
# Usage: envload [.env file]
envload() {
    local envfile="${1:-.env}"
    if [[ ! -f "$envfile" ]]; then
        echo "[qol] File not found: $envfile" >&2
        return 1
    fi

    local line key value count=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and blank lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        # Remove 'export ' prefix if present
        line="${line#export }"

        # Validate KEY=VALUE format (key must be a valid identifier)
        if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            # Strip surrounding quotes
            value="${value%\"}"
            value="${value#\"}"
            value="${value%\'}"
            value="${value#\'}"
            export "$key=$value"
            (( count++ ))
        else
            echo "[qol] Skipping malformed line: $line" >&2
        fi
    done < "$envfile"

    echo "[qol] Loaded ${count} variables from ${envfile}."
}
alias dotenv='envload'

# clipcopy / clippaste: Cross-platform clipboard helpers
clipcopy() {
    if has_cmd pbcopy; then
        pbcopy
    elif has_cmd wl-copy; then
        wl-copy
    elif has_cmd xclip; then
        xclip -selection clipboard
    elif has_cmd xsel; then
        xsel --clipboard --input
    elif has_cmd clip.exe; then
        clip.exe
    else
        echo "[qol] No clipboard tool found (pbcopy, wl-copy, xclip, xsel, clip.exe)." >&2
        return 1
    fi
}

clippaste() {
    if has_cmd pbpaste; then
        pbpaste
    elif has_cmd wl-paste; then
        wl-paste
    elif has_cmd xclip; then
        xclip -selection clipboard -o
    elif has_cmd xsel; then
        xsel --clipboard --output
    elif has_cmd powershell.exe; then
        powershell.exe -NoProfile -Command Get-Clipboard
    else
        echo "[qol] No clipboard paste tool found (pbpaste, wl-paste, xclip, xsel, powershell.exe)." >&2
        return 1
    fi
}

# backup: Copy files/directories with a timestamped .bak suffix
backup() {
    [[ "$#" -eq 0 ]] && { echo "Usage: backup <path> [path2 ...]" >&2; return 1; }

    local src dest status=0 stamp
    stamp="$(date '+%Y%m%d-%H%M%S')"
    for src in "$@"; do
        if [[ ! -e "$src" ]]; then
            echo "[qol] Not found: $src" >&2
            status=1
            continue
        fi
        dest="${src}.bak.${stamp}"
        command cp -a "$src" "$dest" && echo "[qol] Backed up $src -> $dest" || status=1
    done
    return "$status"
}

# sha256: Print SHA-256 checksums using the available platform tool
sha256() {
    if has_cmd sha256sum; then
        sha256sum "$@"
    elif has_cmd shasum; then
        shasum -a 256 "$@"
    else
        echo "[qol] sha256 requires sha256sum or shasum." >&2
        return 1
    fi
}

# =============================================================================
# SECTION 8: JSON HELPERS
# =============================================================================

if has_cmd jq; then
    __qol_feature "json" "jq"

    # jpp: Pretty-print JSON from stdin or file
    jpp() {
        if [[ -n "$1" ]]; then
            jq '.' "$1"
        else
            jq '.'
        fi
    }

    # jkeys: List top-level keys of a JSON object
    jkeys() {
        jq 'keys[]' "${1:--}"
    }

    # jlen: Count items in a JSON array or object
    jlen() {
        jq 'length' "${1:--}"
    }
else
    __qol_warn "jq" "Install 'jq' for JSON helpers (jpp, jkeys, jlen)."
fi

# =============================================================================
# SECTION 9: HTTP HELPERS
# =============================================================================

# A thin wrapper that prefers httpie > curl > wget
# Usage: GET <url>
GET() {
    if has_cmd http; then
        http GET "$@"
    elif has_cmd curl; then
        curl -sSL "$@"
    elif has_cmd wget; then
        wget -qO- "$@"
    else
        echo "[qol] GET requires httpie, curl, or wget." >&2
        return 1
    fi
}

POST() {
    if has_cmd http; then
        http POST "$@"
    elif has_cmd curl; then
        curl -sSL -X POST "$@"
    else
        echo "[qol] POST requires httpie or curl." >&2; return 1
    fi
}

# =============================================================================
# SECTION 10: GIT HELPERS
# =============================================================================

if [[ "${QOL_ENABLE_GIT}" == "1" ]] && has_cmd git; then
    __qol_feature "git" "enabled"

    # Core aliases
    alias gs='git status -sb'
    alias ga='git add'
    alias gaa='git add -A'
    alias gc='git commit'
    alias gcm='git commit -m'
    alias gca='git commit --amend'
    alias gco='git checkout'
    alias gcob='git checkout -b'
    alias gd='git diff'
    alias gds='git diff --staged'
    alias gf='git fetch --all --prune'
    alias gp='git push'
    alias gpf='git push --force-with-lease'
    alias gl='git pull --rebase'
    alias gb='git branch'
    alias gba='git branch -a'
    alias gsw='git switch'
    alias gswc='git switch -c'
    alias gst='git stash'
    alias gstp='git stash pop'
    alias glog='git log --oneline --graph --decorate --all'

    # groot: Jump to repository root
    groot() {
        local root
        root=$(git rev-parse --show-toplevel 2>/dev/null)
        if [[ -z "$root" ]]; then
            echo "[qol] Not in a git repository." >&2
            return 1
        fi
        cd "$root" || return 1
    }

    # gundo: Undo last commit, keep changes staged
    gundo() {
        git reset --soft HEAD~1
    }

    # gclean_merged: Delete local branches already merged into current branch
    gclean_merged() {
        local current
        current=$(git branch --show-current)
        echo "[qol] Cleaning branches merged into: ${current}"
        git branch --merged | command grep -v "^\*" | command grep -v "^\s*${current}$" | command grep -v "^\s*\(main\|master\|develop\|dev\)$" | xargs -r git branch -d
    }

    # gbranch: Fuzzy-pick a branch (uses fzf if available)
    gbranch() {
        if has_cmd fzf && [[ "${QOL_ENABLE_FZF}" == "1" ]]; then
            local branch
            branch=$(git branch -a --format='%(refname:short)' | fzf --height 40% --reverse)
            [[ -n "$branch" ]] && git checkout "$branch"
        else
            git branch -a
        fi
    }

    # gsave: Quick WIP commit
    gsave() {
        git add -A && git commit -m "WIP: $(date '+%Y-%m-%d %H:%M')"
    }

    # grestore: Unstage everything (opposite of gaa)
    grestore() {
        git restore --staged .
    }

    # grecent: Show recently updated local branches
    grecent() {
        git for-each-ref --sort=-committerdate --count="${1:-15}" \
            --format='%(committerdate:relative)%09%(refname:short)%09%(subject)' refs/heads/
    }

    # gignored: Explain why a path is ignored
    gignored() {
        [[ -z "$1" ]] && { echo "Usage: gignored <path>" >&2; return 1; }
        git check-ignore -v "$@"
    }

    # gwip: Stash all tracked/untracked changes with a timestamped message
    gwip() {
        git stash push -u -m "WIP: $(date '+%Y-%m-%d %H:%M')"
    }
else
    [[ "${QOL_ENABLE_GIT}" == "1" ]] && __qol_warn "git" "Install 'git' to enable git helpers."
fi

# =============================================================================
# SECTION 10B: GITHUB CLI HELPERS
# =============================================================================

if [[ "${QOL_ENABLE_GH}" == "1" ]] && has_cmd gh; then
    __qol_feature "gh" "enabled"

    alias ghpr='gh pr status'
    alias ghprs='gh pr list'
    alias ghci='gh run list --limit 10'

    # ghopen: Open the current repo or a specific path in GitHub
    ghopen() {
        gh repo view --web "$@"
    }

    # ghmine: Show issues and PRs assigned to the current user
    ghmine() {
        gh issue list --assignee @me
        gh pr list --author @me
    }
else
    [[ "${QOL_ENABLE_GH}" == "1" ]] && __qol_warn "gh" "Install 'gh' to enable GitHub CLI helpers."
fi

# =============================================================================
# SECTION 11: DOCKER HELPERS
# =============================================================================

if [[ "${QOL_ENABLE_DOCKER}" == "1" ]] && has_cmd docker; then
    __qol_feature "docker" "enabled"

    alias dk='docker'
    alias dkps='docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
    alias dkpsa='docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
    alias dki='docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"'

    # dkc: docker compose wrapper with docker-compose fallback
    dkc() {
        if docker compose version &>/dev/null; then
            docker compose "$@"
        elif has_cmd docker-compose; then
            docker-compose "$@"
        else
            echo "[qol] Docker Compose not found (docker compose or docker-compose)." >&2
            return 1
        fi
    }

    # dksh: Shell into a running container (defaults to sh if bash not available)
    dksh() {
        local container="${1:-}"
        if [[ -z "$container" ]]; then
            if has_cmd fzf && [[ "${QOL_ENABLE_FZF}" == "1" ]]; then
                container=$(docker ps --format '{{.Names}}' | fzf --height 40% --reverse)
            else
                echo "Usage: dksh <container_name>" >&2
                return 1
            fi
        fi
        docker exec -it "$container" bash 2>/dev/null || docker exec -it "$container" sh
    }

    # dkclean: Remove stopped containers, dangling images, unused networks
    dkclean() {
        echo "[qol] Pruning Docker resources..."
        docker system prune -f
    }

    # dklogs: Tail logs for a container
    dklogs() {
        local container="${1:-}"
        [[ -z "$container" ]] && { echo "Usage: dklogs <container>" >&2; return 1; }
        docker logs -f --tail=100 "$container"
    }

    # dkclean_all: Prompt, then prune containers/images/volumes/build cache
    dkclean_all() {
        read -r -p "[qol] Prune all unused Docker resources, including volumes? [y/N] " answer
        [[ "$answer" =~ ^[Yy]$ ]] || return 0
        docker system prune -af --volumes
    }
else
    [[ "${QOL_ENABLE_DOCKER}" == "1" ]] && __qol_warn "docker" "Install 'docker' to enable Docker helpers."
fi


# =============================================================================
# SECTION 11B: PODMAN HELPERS
# =============================================================================

if [[ "${QOL_ENABLE_PODMAN}" == "1" ]] && has_cmd podman; then
    __qol_feature "podman" "enabled"

    alias pm='podman'
    alias pmps='podman ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
    alias pmpsa='podman ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
    alias pmi='podman images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"'
    alias pmv='podman volume ls'
    alias pmn='podman network ls'

    # pmc: podman compose wrapper
    # Usage: pmc up -d
    pmc() {
        if podman compose version &>/dev/null; then
            podman compose "$@"
        elif has_cmd podman-compose; then
            podman-compose "$@"
        else
            echo "[qol] Podman Compose not found (podman compose or podman-compose)." >&2
            return 1
        fi
    }

    # pmsh: Shell into a running Podman container
    # Usage: pmsh [container]
    pmsh() {
        local container="${1:-}"
        if [[ -z "$container" ]]; then
            if has_cmd fzf && [[ "${QOL_ENABLE_FZF}" == "1" ]]; then
                container=$(podman ps --format '{{.Names}}' | fzf --height 40% --reverse)
            else
                echo "Usage: pmsh <container_name>" >&2
                return 1
            fi
        fi
        [[ -z "$container" ]] && return 1
        podman exec -it "$container" bash 2>/dev/null || podman exec -it "$container" sh
    }

    # pmlogs: Tail logs for a container
    # Usage: pmlogs <container>
    pmlogs() {
        local container="${1:-}"
        [[ -z "$container" ]] && { echo "Usage: pmlogs <container>" >&2; return 1; }
        podman logs -f --tail=100 "$container"
    }

    # pmclean: Remove stopped containers, dangling images, unused networks
    pmclean() {
        echo "[qol] Pruning Podman resources..."
        podman system prune -f
    }

    # pmclean_all: Prompt, then prune containers/images/volumes
    pmclean_all() {
        read -r -p "[qol] Prune all unused Podman resources, including volumes? [y/N] " answer
        [[ "$answer" =~ ^[Yy]$ ]] || return 0
        podman system prune -af --volumes
    }

    # pmip: Show container IP address
    # Usage: pmip <container>
    pmip() {
        local container="${1:-}"
        [[ -z "$container" ]] && { echo "Usage: pmip <container>" >&2; return 1; }
        podman inspect -f '{{.NetworkSettings.IPAddress}}' "$container"
    }
else
    [[ "${QOL_ENABLE_PODMAN}" == "1" ]] && __qol_warn "podman" "Install 'podman' to enable Podman helpers."
fi

# =============================================================================
# SECTION 12: KUBERNETES HELPERS
# =============================================================================

if [[ "${QOL_ENABLE_K8S}" == "1" ]] && has_cmd kubectl; then
    __qol_feature "k8s" "enabled"

    alias k='kubectl'
    alias kgp='kubectl get pods'
    alias kgpa='kubectl get pods -A'
    alias kgs='kubectl get svc'
    alias kgn='kubectl get nodes'
    alias kd='kubectl describe'
    alias kl='kubectl logs -f'
    alias ke='kubectl exec -it'
    alias kns='kubectl config set-context --current --namespace'

    # kubens: Switch namespace (fzf-enhanced)
    kubens() {
        if has_cmd fzf && [[ "${QOL_ENABLE_FZF}" == "1" ]]; then
            local ns
            ns=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | fzf --height 40%)
            [[ -n "$ns" ]] && kubectl config set-context --current --namespace="$ns"
        else
            kubectl get namespaces
        fi
    }

    # kubectx: Switch context (fzf-enhanced)
    kubectx() {
        if has_cmd fzf && [[ "${QOL_ENABLE_FZF}" == "1" ]]; then
            local ctx
            ctx=$(kubectl config get-contexts -o name | fzf --height 40%)
            [[ -n "$ctx" ]] && kubectl config use-context "$ctx"
        else
            kubectl config get-contexts
        fi
    }

    # Shell completion if available
    if [[ "${__QOL_FIRST_LOAD}" == "1" ]] && kubectl completion bash &>/dev/null; then
        # shellcheck disable=SC1090
        source <(kubectl completion bash)
        alias k='kubectl'
        complete -o default -F __start_kubectl k
    fi
else
    [[ "${QOL_ENABLE_K8S}" == "1" ]] && __qol_warn "kubectl" "Install 'kubectl' to enable Kubernetes helpers."
fi

# =============================================================================
# SECTION 13: TMUX HELPERS
# =============================================================================

if [[ "${QOL_ENABLE_TMUX}" == "1" ]] && has_cmd tmux; then
    __qol_feature "tmux" "enabled"

    alias ta='tmux attach -t'
    alias tls='tmux list-sessions'
    alias tn='tmux new -s'
    alias twl='tmux list-windows'
    alias tpl='tmux list-panes'
    alias trn='tmux rename-session'
    alias trw='tmux rename-window'

    # t: Attach to an existing tmux session or create one
    # Usage: t [session]
    t() {
        local session="${1:-main}"
        tmux attach -t "$session" 2>/dev/null || tmux new -s "$session"
    }

    # tk: Kill a tmux session after confirmation
    # Usage: tk <session>
    tk() {
        local session="${1:-}"
        [[ -z "$session" ]] && { echo "Usage: tk <session>" >&2; return 1; }
        read -r -p "[qol] Kill tmux session '${session}'? [y/N] " answer
        [[ "$answer" =~ ^[Yy]$ ]] && tmux kill-session -t "$session"
    }

    # tks: Kill the current tmux session after confirmation
    tks() {
        [[ -z "${TMUX:-}" ]] && { echo "[qol] Not inside tmux." >&2; return 1; }
        local session
        session="$(tmux display-message -p '#S')"
        read -r -p "[qol] Kill current tmux session '${session}'? [y/N] " answer
        [[ "$answer" =~ ^[Yy]$ ]] && tmux kill-session -t "$session"
    }

    # tw: Create a new tmux window
    # Usage: tw [name] [command...]
    tw() {
        local name="${1:-}"
        if [[ -n "$name" ]]; then
            shift
            if [[ "$#" -gt 0 ]]; then
                tmux new-window -n "$name" "$*"
            else
                tmux new-window -n "$name"
            fi
        else
            tmux new-window
        fi
    }

    # twa: Attach/create session with named first window
    # Usage: twa <session> [window]
    twa() {
        local session="${1:-main}"
        local window="${2:-shell}"
        tmux new-session -A -s "$session" -n "$window"
    }

    # tsw: Switch tmux session, fzf-enhanced when available
    # Usage: tsw [session]
    tsw() {
        local session="${1:-}"
        if [[ -z "$session" ]]; then
            if has_cmd fzf && [[ "${QOL_ENABLE_FZF}" == "1" ]]; then
                session="$(tmux list-sessions -F '#S' 2>/dev/null | fzf --height 40% --reverse)"
            else
                echo "Usage: tsw <session>" >&2
                tmux list-sessions
                return 1
            fi
        fi
        [[ -n "$session" ]] && tmux switch-client -t "$session"
    }

    # tsp: Split pane
    # Usage: tsp [h|v] [command...]
    #   h = horizontal split, v = vertical split
    tsp() {
        local direction="${1:-v}"
        shift || true

        case "$direction" in
            h|horizontal)
                if [[ "$#" -gt 0 ]]; then
                    tmux split-window -h "$*"
                else
                    tmux split-window -h
                fi
                ;;
            v|vertical)
                if [[ "$#" -gt 0 ]]; then
                    tmux split-window -v "$*"
                else
                    tmux split-window -v
                fi
                ;;
            *)
                echo "Usage: tsp [h|v] [command...]" >&2
                return 1
                ;;
        esac
    }

    # tsh: Horizontal split
    # Usage: tsh [command...]
    tsh() {
        if [[ "$#" -gt 0 ]]; then
            tmux split-window -h "$*"
        else
            tmux split-window -h
        fi
    }

    # tsv: Vertical split
    # Usage: tsv [command...]
    tsv() {
        if [[ "$#" -gt 0 ]]; then
            tmux split-window -v "$*"
        else
            tmux split-window -v
        fi
    }

    # tx: Send a command to a pane
    # Usage: tx <target-pane> <command...>
    # Example: tx :.1 "npm test"
    tx() {
        local target="${1:-}"
        shift || true
        [[ -z "$target" || "$#" -eq 0 ]] && {
            echo "Usage: tx <target-pane> <command...>" >&2
            echo "Example: tx :.1 \"npm test\"" >&2
            return 1
        }
        tmux send-keys -t "$target" "$*" C-m
    }

    # txc: Send command to current pane
    # Usage: txc <command...>
    txc() {
        [[ "$#" -eq 0 ]] && { echo "Usage: txc <command...>" >&2; return 1; }
        tmux send-keys "$*" C-m
    }

    # tclear: Clear current pane
    tclear() {
        tmux send-keys C-l
    }

    # tlayout: Apply a tmux layout
    # Usage: tlayout even-horizontal|even-vertical|main-horizontal|main-vertical|tiled
    tlayout() {
        local layout="${1:-tiled}"
        tmux select-layout "$layout"
    }

    # tzoom: Toggle pane zoom
    tzoom() {
        tmux resize-pane -Z
    }

    # tnext / tprev: Move between windows
    tnext() {
        tmux next-window
    }

    tprev() {
        tmux previous-window
    }

    # tpane: Select pane by number
    # Usage: tpane <pane-number>
    tpane() {
        local pane="${1:-}"
        [[ -z "$pane" ]] && { echo "Usage: tpane <pane-number>" >&2; return 1; }
        tmux select-pane -t "$pane"
    }
else
    [[ "${QOL_ENABLE_TMUX}" == "1" ]] && __qol_warn "tmux" "Install 'tmux' to enable tmux helpers."
fi

# =============================================================================
# SECTION 14: LANGUAGE/RUNTIME HELPERS
# =============================================================================

# --- Node / npm ---
if [[ "${QOL_ENABLE_NODE}" == "1" ]] && has_cmd node; then
    __qol_feature "node" "enabled"
    alias ni='npm install'
    alias nid='npm install --save-dev'
    alias nig='npm install -g'
    alias nr='npm run'
    alias ns='npm start'
    alias nt='npm test'
    alias nb='npm run build'
    alias nls='npm list --depth=0'

    # Use pnpm aliases if available
    if has_cmd pnpm; then
        alias pi='pnpm install'
        alias pr='pnpm run'
        alias pa='pnpm add'
        alias pad='pnpm add -D'
    fi

    # node_modules bin path helper
    npm_bin() {
        echo "$(npm prefix)/node_modules/.bin"
    }
fi

# --- Python ---
if [[ "${QOL_ENABLE_PYTHON}" == "1" ]] && (has_cmd python3 || has_cmd python); then
    __qol_feature "python" "enabled"

    # Normalize python command
    if has_cmd python3 && ! has_cmd python; then
        alias python='python3'
        alias pip='pip3'
    fi

    # venv: Create and activate a virtualenv
    venv() {
        local name="${1:-.venv}"
        if [[ ! -d "$name" ]]; then
            python3 -m venv "$name" || { echo "[qol] Failed to create venv." >&2; return 1; }
            echo "[qol] Created virtualenv: $name"
        fi
        # shellcheck disable=SC1091
        source "${name}/bin/activate"
        echo "[qol] Activated: $name"
    }

    # pyrun: Run a Python one-liner cleanly
    pyrun() {
        python3 -c "$@"
    }
fi

# --- Rust / Cargo ---
if [[ "${QOL_ENABLE_RUST}" == "1" ]] && has_cmd cargo; then
    __qol_feature "rust" "enabled"
    alias cb='cargo build'
    alias cr='cargo run'
    alias ct='cargo test'
    alias cc='cargo check'
    alias cf='cargo fmt'
    alias ccl='cargo clippy'
fi

# =============================================================================
# SECTION 15: FZF INTEGRATIONS
# =============================================================================

if [[ "${QOL_ENABLE_FZF}" == "1" ]] && has_cmd fzf; then
    __qol_feature "fzf" "enabled"

    # Load fzf shell integration if available
    if [[ "${__QOL_FIRST_LOAD}" == "1" ]] && [[ -f ~/.fzf.bash ]]; then
        # shellcheck disable=SC1090
        source ~/.fzf.bash
    elif [[ "${__QOL_FIRST_LOAD}" == "1" ]] && [[ -f /usr/share/doc/fzf/examples/key-bindings.bash ]]; then
        # shellcheck disable=SC1091
        source /usr/share/doc/fzf/examples/key-bindings.bash
    fi

    # fh: Search command history interactively
    fh() {
        local cmd
        cmd=$(fc -rl 1 | awk '{$1=""; print $0}' | sort -u | fzf --height 40% --reverse --query="${1:-}")
        if [[ -n "$cmd" ]]; then
            history -s "$cmd"
            eval "$cmd"
        fi
    }

    # fcd: Fuzzy-find and cd to a directory
    fcd() {
        local dir
        if has_cmd fd; then
            dir=$(fd --type d "${1:-.}" 2>/dev/null | fzf --height 40% --reverse)
        else
            dir=$(find "${1:-.}" -type d 2>/dev/null | fzf --height 40% --reverse)
        fi
        [[ -n "$dir" ]] && cd "$dir" || return 1
    }

    # fkill: Fuzzy kill a process
    fkill() {
        local pid
        pid=$(ps aux | tail -n +2 | fzf --height 40% --reverse | awk '{print $2}')
        if [[ -n "$pid" ]]; then
            echo "[qol] Killing PID: $pid"
            kill -9 "$pid"
        fi
    }

    # fenv: Fuzzy search environment variables
    fenv() {
        env | sort | fzf --height 40% --reverse --query="${1:-}"
    }

    export FZF_DEFAULT_OPTS='--height 40% --reverse --border --color=hl:yellow,hl+:yellow'
    if has_cmd fd; then
        export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
        export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    fi
else
    __qol_warn "fzf" "Install 'fzf' for interactive fuzzy-finding (fh, fcd, fkill, gbranch)."
fi

# =============================================================================
# SECTION 16: ZOXIDE INTEGRATION
# =============================================================================

if [[ "${QOL_ENABLE_ZOXIDE}" == "1" ]] && has_cmd zoxide; then
    __qol_feature "zoxide" "enabled"
    # shellcheck disable=SC1090
    [[ "${__QOL_FIRST_LOAD}" == "1" ]] && eval "$(zoxide init bash)"
    # z is set by zoxide; add zi for interactive selection
    if has_cmd fzf; then
        alias zi='z -i'
    fi
else
    __qol_warn "zoxide" "Install 'zoxide' for smart directory jumping (z command)."
fi

# =============================================================================
# SECTION 17: DIRENV INTEGRATION
# =============================================================================

if [[ "${QOL_ENABLE_DIRENV}" == "1" ]] && has_cmd direnv; then
    __qol_feature "direnv" "enabled"
    # shellcheck disable=SC1090
    [[ "${__QOL_FIRST_LOAD}" == "1" ]] && eval "$(direnv hook bash)"
else
    __qol_warn "direnv" "Install 'direnv' for automatic per-directory env management."
fi

# =============================================================================
# SECTION 18: PROMPT SETUP
# =============================================================================

if [[ "${QOL_ENABLE_PROMPT}" == "1" ]]; then
    if has_cmd starship; then
        __qol_feature "prompt" "starship"
        # shellcheck disable=SC1090
        [[ "${__QOL_FIRST_LOAD}" == "1" ]] && eval "$(starship init bash)"
    else
        __qol_warn "starship" "Install 'starship' for a beautiful cross-shell prompt."
        __qol_feature "prompt" "builtin"

        # Minimal but informative fallback prompt
        # Shows: user@host path [git branch] [exit status indicator]
        __qol_prompt_git_branch() {
            local branch
            branch=$(git symbolic-ref --short HEAD 2>/dev/null) || \
            branch=$(git rev-parse --short HEAD 2>/dev/null)
            [[ -n "$branch" ]] && printf ' (\001\033[33m\002%s\001\033[0m\002)\n' "$branch"
        }

        __qol_prompt_exit() {
            local exit_code=$?
            if (( exit_code != 0 )); then
                printf '\001\033[31m\002✖ %s\001\033[0m\002 \n' "$exit_code"
            fi
        }

        # Colors
        __QOL_C_RESET='\[\033[0m\]'
        __QOL_C_GREEN='\[\033[32m\]'
        __QOL_C_BLUE='\[\033[34m\]'
        __QOL_C_CYAN='\[\033[36m\]'
        __QOL_C_BOLD='\[\033[1m\]'

        # Two-line prompt: path + git on first, $ on second
        __qol_set_prompt() {
            local exit_code=$?
            local exit_indicator=""
            (( exit_code != 0 )) && exit_indicator="\[\033[31m\]✖ ${exit_code}\[\033[0m\] "

            local git_part
            git_part=$(__qol_prompt_git_branch)

            PS1="${__QOL_C_BOLD}${__QOL_C_GREEN}\u\[\033[0m\]@${__QOL_C_CYAN}\h\[\033[0m\] ${__QOL_C_BLUE}\w\[\033[0m\]${git_part}\n${exit_indicator}${__QOL_C_BOLD}\$\[\033[0m\] "
        }

        # Only add if not already in PROMPT_COMMAND
        if [[ "${PROMPT_COMMAND}" != *"__qol_set_prompt"* ]]; then
            PROMPT_COMMAND="${PROMPT_COMMAND:+${PROMPT_COMMAND}; }__qol_set_prompt"
        fi
    fi
fi

# =============================================================================
# SECTION 19: SHELL OPTIONS & HISTORY
# =============================================================================

# Better history
HISTSIZE=10000
HISTFILESIZE=20000
HISTCONTROL=ignoreboth:erasedups   # Ignore duplicates & lines starting with space
HISTIGNORE="ls:ll:cd:pwd:exit:clear:history:c:h"
shopt -s histappend                 # Append rather than overwrite history file
shopt -s cmdhist                    # Multi-line commands in one history entry

# Quality of life shell options
shopt -s checkwinsize               # Update LINES/COLUMNS after each command
shopt -s globstar 2>/dev/null       # Enable **glob (Bash 4+)
shopt -s nocaseglob 2>/dev/null     # Case-insensitive globbing
shopt -s cdspell 2>/dev/null        # Auto-fix minor typos in cd paths
shopt -s dirspell 2>/dev/null       # Auto-fix typos when completing directory names
shopt -s autocd 2>/dev/null         # Type a directory name to cd into it (Bash 4+)

# Make less more friendly
export LESS='-R --quit-if-one-screen --ignore-case'
export LESSHISTFILE=/dev/null       # Don't pollute $HOME with .lesshst

# Enable color support in man pages (if bat available)
if has_cmd bat; then
    export MANPAGER="sh -c 'col -bx | bat -l man -p'"
elif has_cmd most; then
    export MANPAGER=most
fi

# Default editor
if [[ -z "${EDITOR:-}" ]]; then
    if has_cmd nvim; then
        export EDITOR=nvim
    elif has_cmd vim; then
        export EDITOR=vim
    elif has_cmd nano; then
        export EDITOR=nano
    fi
fi

# =============================================================================
# SECTION 20: DOCTOR & HELP
# =============================================================================

# qol_doctor: Health report for the QOL environment
qol_doctor() {
    local GREEN='\033[32m' RED='\033[31m' CYAN='\033[36m' RESET='\033[0m' BOLD='\033[1m'

    echo -e "${BOLD}╔══════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}║       terminal-qol :: Doctor         ║${RESET}"
    echo -e "${BOLD}╚══════════════════════════════════════╝${RESET}"
    echo

    # System info
    echo -e "${CYAN}System:${RESET}"
    echo "  OS:      $(uname -srm)"
    echo "  Bash:    ${BASH_VERSION}"
    echo "  Shell:   ${SHELL}"
    echo "  User:    $(whoami)"
    echo

    # Load time
    if [[ -n "${__QOL_LOAD_TIME_START:-}" ]] && [[ -n "${EPOCHREALTIME:-}" ]]; then
        local elapsed
        elapsed=$(awk "BEGIN { printf \"%.0fms\", (${EPOCHREALTIME} - ${__QOL_LOAD_TIME_START}) * 1000 }")
        echo -e "${CYAN}Load time:${RESET} ${elapsed} (approximate)"
        echo
    fi

    # Active features
    echo -e "${CYAN}Active Features:${RESET}"
    for feature in "${!__QOL_FEATURES[@]}"; do
        printf "  %-20s %s\n" "${feature}:" "${__QOL_FEATURES[$feature]}"
    done | sort
    echo

    # Tool availability
    echo -e "${CYAN}Tool Status:${RESET}"
    local tools=(
        "git:Git version control"
        "eza:Modern ls replacement"
        "bat:Syntax-highlighted cat"
        "rg:Fast grep (ripgrep)"
        "fd:Fast find"
        "fzf:Fuzzy finder"
        "zoxide:Smart cd"
        "direnv:Per-dir env loading"
        "starship:Cross-shell prompt"
        "delta:Better git diffs"
        "jq:JSON processor"
        "docker:Container runtime"
        "podman:Container runtime"
        "kubectl:Kubernetes CLI"
        "node:Node.js runtime"
        "python3:Python 3"
        "cargo:Rust build tool"
        "nvim:Neovim editor"
        "tmux:Terminal multiplexer"
        "gh:GitHub CLI"
        "http:HTTPie client"
    )

    for entry in "${tools[@]}"; do
        local cmd="${entry%%:*}"
        local desc="${entry#*:}"
        if has_cmd "$cmd"; then
            local ver
            ver=$("$cmd" --version 2>/dev/null | head -1 | command grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
            printf "  ${GREEN}✔${RESET} %-14s %-28s %s\n" "$cmd" "$desc" "${ver:+(v${ver})}"
        else
            printf "  ${RED}✘${RESET} %-14s %s\n" "$cmd" "$desc"
        fi
    done
    echo

    # Configuration
    echo -e "${CYAN}Configuration:${RESET}"
    echo "  QOL_ENABLE_GIT=${QOL_ENABLE_GIT}  QOL_ENABLE_DOCKER=${QOL_ENABLE_DOCKER}  QOL_ENABLE_K8S=${QOL_ENABLE_K8S}"
    echo "  QOL_ENABLE_PROMPT=${QOL_ENABLE_PROMPT}  QOL_SAFE_ALIASES=${QOL_SAFE_ALIASES}  QOL_WARN_MISSING=${QOL_WARN_MISSING}"
    echo "  QOL_ENABLE_FZF=${QOL_ENABLE_FZF}  QOL_ENABLE_ZOXIDE=${QOL_ENABLE_ZOXIDE}  QOL_ENABLE_DIRENV=${QOL_ENABLE_DIRENV}"
    echo "  QOL_ENABLE_GH=${QOL_ENABLE_GH}  QOL_ENABLE_TMUX=${QOL_ENABLE_TMUX}  QOL_ENABLE_PODMAN=${QOL_ENABLE_PODMAN}"
}

# qol_help: List all user-facing functions and aliases
qol_help() {
    local BOLD='\033[1m' CYAN='\033[36m' GREEN='\033[32m' RESET='\033[0m'

    echo -e "${BOLD}╔══════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}║       terminal-qol :: Help           ║${RESET}"
    echo -e "${BOLD}╚══════════════════════════════════════╝${RESET}"
    echo

    echo -e "${CYAN}Navigation:${RESET}"
    echo "  mkcd <dir>          Create directory and cd into it"
    echo "  up [N]              Move up N directories (default: 1)"
    echo "  groot               Jump to git repository root"
    echo "  fcd                 Fuzzy-find and cd to directory (requires fzf)"
    echo "  z <query>           Smart jump (requires zoxide)"
    echo

    echo -e "${CYAN}Files & Archives:${RESET}"
    echo "  extract <file>      Extract any common archive format"
    echo "  path                Print PATH one entry per line"
    echo "  path_add <dir>      Safely prepend dir to PATH (no duplicates)"
    echo "  path_add_back <dir> Safely append dir to PATH"
    echo "  path_rm <dir>       Remove dir from PATH"
    echo "  path_dedupe         Remove duplicate PATH entries"
    echo "  backup <path>       Create timestamped .bak copy"
    echo "  sha256 <file>       Print SHA-256 checksum"
    echo

    echo -e "${CYAN}Network & Servers:${RESET}"
    echo "  serve [port]        Start HTTP server in current dir (default: 8080)"
    echo "  ports               List all listening ports"
    echo "  port_kill <port>    Kill process listening on port"
    echo "  psg <pattern>       Search running processes"
    echo "  GET <url>           HTTP GET (uses httpie > curl > wget)"
    echo "  POST <url>          HTTP POST"
    echo

    echo -e "${CYAN}Environment:${RESET}"
    echo "  envload [file]      Load .env file safely (default: .env)"
    echo "  dotenv [file]       Alias for envload"
    echo "  clipcopy            Copy stdin to system clipboard"
    echo "  clippaste           Print system clipboard contents"
    echo "  reload_shell        Reload ~/.bashrc"
    echo "  please              Re-run last command with sudo"
    echo

    echo -e "${CYAN}JSON (requires jq):${RESET}"
    echo "  jpp [file]          Pretty-print JSON"
    echo "  jkeys [file]        List top-level keys"
    echo "  jlen [file]         Count items in array/object"
    echo

    echo -e "${CYAN}Git (QOL_ENABLE_GIT=1):${RESET}"
    echo "  gs                  git status -sb"
    echo "  ga / gaa            git add / git add -A"
    echo "  gc / gcm / gca      git commit / -m / --amend"
    echo "  gco / gcob          git checkout / -b"
    echo "  gsw / gswc          git switch / switch -c"
    echo "  gd / gds            git diff / --staged"
    echo "  glog                git log --oneline --graph --decorate --all"
    echo "  groot               Jump to repo root"
    echo "  gundo               Undo last commit (keep changes staged)"
    echo "  gclean_merged       Delete merged local branches"
    echo "  gbranch             Fuzzy-pick branch (fzf)"
    echo "  grecent             Show recently updated branches"
    echo "  gignored <path>     Explain why a path is ignored"
    echo "  gwip                Stash tracked/untracked changes as WIP"
    echo "  gsave               Quick WIP commit with timestamp"
    echo

    echo -e "${CYAN}GitHub CLI (QOL_ENABLE_GH=1):${RESET}"
    echo "  ghpr / ghprs        PR status / list PRs"
    echo "  ghci                List recent workflow runs"
    echo "  ghopen              Open current repo in GitHub"
    echo "  ghmine              Show assigned issues and authored PRs"
    echo

    echo -e "${CYAN}Docker (QOL_ENABLE_DOCKER=1):${RESET}"
    echo "  dkps / dkpsa        List running / all containers"
    echo "  dki                 List images"
    echo "  dkc                 docker compose wrapper"
    echo "  dksh [container]    Shell into container"
    echo "  dkclean             Prune unused Docker resources"
    echo "  dkclean_all         Prune Docker resources including volumes"
    echo "  dklogs <container>  Tail container logs"
    echo

    echo -e "${CYAN}Podman (QOL_ENABLE_PODMAN=1):${RESET}"
    echo "  pm                  podman"
    echo "  pmps / pmpsa        List running / all containers"
    echo "  pmi                 List images"
    echo "  pmc                 podman compose wrapper"
    echo "  pmsh [container]    Shell into container"
    echo "  pmlogs <container>  Tail container logs"
    echo "  pmclean             Prune unused Podman resources"
    echo "  pmclean_all         Prune Podman resources including volumes"
    echo "  pmip <container>    Show container IP address"
    echo

    echo -e "${CYAN}Kubernetes (QOL_ENABLE_K8S=1):${RESET}"
    echo "  k                   kubectl"
    echo "  kgp / kgpa          get pods / all namespaces"
    echo "  kl / ke             logs / exec"
    echo "  kubens              Switch namespace (fzf)"
    echo "  kubectx             Switch context (fzf)"
    echo

    echo -e "${CYAN}tmux (QOL_ENABLE_TMUX=1):${RESET}"
    echo "  t [session]         Attach or create tmux session"
    echo "  tls / tn / ta       list / new / attach sessions"
    echo "  tk <session>        Kill a session after confirmation"
    echo "  tks                 Kill current session after confirmation"
    echo "  tw [name] [cmd]     Create new window"
    echo "  twa <session> [win] Attach/create session with named window"
    echo "  tsw [session]       Switch session, fzf-enhanced"
    echo "  tsh / tsv [cmd]     Split pane horizontally / vertically"
    echo "  tsp [h|v] [cmd]     Split pane by direction"
    echo "  tx <pane> <cmd>     Send command to target pane"
    echo "  txc <cmd>           Send command to current pane"
    echo "  tclear              Clear current pane"
    echo "  tlayout [layout]    Apply tmux layout"
    echo "  tzoom               Toggle pane zoom"
    echo "  tnext / tprev       Next / previous window"
    echo "  tpane <num>         Select pane by number"
    echo

    echo -e "${CYAN}FZF Helpers (requires fzf):${RESET}"
    echo "  fh                  Fuzzy search command history"
    echo "  fcd                 Fuzzy cd"
    echo "  fkill               Fuzzy kill process"
    echo "  fenv                Fuzzy search env vars"
    echo

    echo -e "${CYAN}Language Shortcuts:${RESET}"
    echo "  venv [name]         Create & activate Python venv (default: .venv)"
    echo "  ni / nr / ns / nt   npm install/run/start/test"
    echo "  cb / cr / ct / cc   cargo build/run/test/check"
    echo

    echo -e "${CYAN}Diagnostics:${RESET}"
    echo "  qol_doctor          Show feature status, tool availability, system info"
    echo "  qol_help            Show this help"
    echo
    echo -e "  Configure: set ${GREEN}QOL_* variables${RESET} before sourcing terminal-qol.bash"
}

# =============================================================================
# SECTION 21: LOAD TIME TRACKING
# =============================================================================

if [[ -n "${__QOL_LOAD_TIME_START:-}" ]] && [[ -n "${EPOCHREALTIME:-}" ]]; then
    __QOL_LOAD_TIME_END="${EPOCHREALTIME}"
    __qol_debug "Loaded in $(awk "BEGIN { printf \"%.0fms\", (${__QOL_LOAD_TIME_END} - ${__QOL_LOAD_TIME_START}) * 1000 }")"
fi

# Final marker
__QOL_READY=1
