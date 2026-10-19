#!/usr/bin/env bats
# test_install.bats - Integration tests for install.sh
#
# Tests installer behavior with mocked network downloads.

# Load test helpers
load '../helpers/test_helper'

# =============================================================================
# Setup and Teardown
# =============================================================================

setup() {
    setup_test_environment
    log_test_start "${BATS_TEST_NAME}"
}

teardown() {
    log_test_end "${BATS_TEST_NAME}" "$([[ ${status:-0} -eq 0 ]] && echo pass || echo fail)"
    teardown_test_environment
}

# =============================================================================
# Mock curl (no network)
# =============================================================================

setup_mock_curl() {
    local mock_bin="$TEST_DIR/bin"
    mkdir -p "$mock_bin"

    cat > "$mock_bin/curl" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

out=""
url=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -o)
            out="$2"
            shift 2
            ;;
        *)
            url="$1"
            shift
            ;;
    esac
done

if [[ -z "$url" ]]; then
    exit 1
fi

if [[ -n "${out:-}" ]]; then
    if [[ "$url" == *"apr.sha256"* ]]; then
        cp "$APR_TEST_REMOTE_SHA" "$out"
    else
        cp "$APR_TEST_REMOTE_APR" "$out"
    fi
else
    if [[ "$url" == *"apr.sha256"* ]]; then
        cat "$APR_TEST_REMOTE_SHA"
    else
        cat "$APR_TEST_REMOTE_APR"
    fi
fi
EOF

    chmod +x "$mock_bin/curl"

    # Ensure curl is found before system binaries
    export PATH="$mock_bin:$PATH"
}

# =============================================================================
# Tests
# =============================================================================

@test "install.sh: installs APR to DEST with APR_SKIP_VERIFY" {
    local remote_apr="$TEST_DIR/remote_apr"
    local remote_sha="$TEST_DIR/remote_apr.sha256"
    cp "$APR_SCRIPT" "$remote_apr"
    echo "dummy" > "$remote_sha"

    export APR_TEST_REMOTE_APR="$remote_apr"
    export APR_TEST_REMOTE_SHA="$remote_sha"
    setup_mock_curl

    local dest_dir="$TEST_DIR/install/bin"

    run env \
        DEST="$dest_dir" \
        APR_NO_DEPS=1 \
        APR_SKIP_VERIFY=1 \
        APR_SKIP_INSTALLER_CHECK=1 \
        NO_COLOR=1 \
        bash "$PROJECT_ROOT/install.sh"

    log_test_output "$output"

    assert_success
    assert_file_exists "$dest_dir/apr"
    [[ -x "$dest_dir/apr" ]]
}

@test "install.sh: verifies checksum when available" {
    if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
        skip "No sha256sum or shasum available"
    fi

    local remote_apr="$TEST_DIR/remote_apr"
    local remote_sha="$TEST_DIR/remote_apr.sha256"
    cp "$APR_SCRIPT" "$remote_apr"

    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$remote_apr" | awk '{print $1}' > "$remote_sha"
    else
        shasum -a 256 "$remote_apr" | awk '{print $1}' > "$remote_sha"
    fi

    export APR_TEST_REMOTE_APR="$remote_apr"
    export APR_TEST_REMOTE_SHA="$remote_sha"
    setup_mock_curl

    local dest_dir="$TEST_DIR/install_checksum/bin"

    run env \
        DEST="$dest_dir" \
        APR_NO_DEPS=1 \
        APR_SKIP_INSTALLER_CHECK=1 \
        NO_COLOR=1 \
        bash "$PROJECT_ROOT/install.sh"

    log_test_output "$output"

    assert_success
    assert_file_exists "$dest_dir/apr"
}

# =============================================================================
# Node.js / Oracle dependency setup (no network, no root: every tool is a stub)
# =============================================================================

# A fresh PATH directory holding only basic tools plus stubs. Stubs append
# their argv to $STUB_LOG; node and npm exist only when a test creates them.
# Usage: setup_dependency_sandbox [name] [uname -s answer, default Linux]
setup_dependency_sandbox() {
    SANDBOX_BIN="$TEST_DIR/${1:-sandbox}-bin"
    STUB_LOG="$TEST_DIR/${1:-sandbox}-calls.log"
    mkdir -p "$SANDBOX_BIN"
    : > "$STUB_LOG"
    local tool
    for tool in grep head cat chmod; do
        ln -s "$(command -v "$tool")" "$SANDBOX_BIN/$tool"
    done
    printf '#!%s\nprintf "%%s\\n" %s\n' "$BASH" "${2:-Linux}" > "$SANDBOX_BIN/uname"
    chmod +x "$SANDBOX_BIN/uname"
    sed '/^main "\$@"$/d' "$PROJECT_ROOT/install.sh" > "$TEST_DIR/install_functions.bash"
}

# make_stub NAME [BODY]: a stub that logs its argv, then runs BODY.
make_stub() {
    printf '#!%s\nprintf "%%s\\n" "%s $*" >> "%s"\n%s\n' "$BASH" "$1" "$STUB_LOG" "${2:-exit 0}" > "$SANDBOX_BIN/$1"
    chmod +x "$SANDBOX_BIN/$1"
}

# node_stub_body MAJOR: script text for a node reporting vMAJOR.1.0.
node_stub_body() {
    printf 'case "$1" in --version) echo v%s.1.0;; -p) echo %s;; esac' "$1" "$1"
}

# installer_puts_node TOOL MAJOR: a package-manager stub TOOL that exits 0
# after "installing" node vMAJOR.1.0 and npm onto the sandbox PATH.
installer_puts_node() {
    local staged="$TEST_DIR/staged-node-$2"
    mkdir -p "$staged"
    printf '#!%s\n%s\n' "$BASH" "$(node_stub_body "$2")" > "$staged/node"
    printf '#!%s\nexit 0\n' "$BASH" > "$staged/npm"
    chmod +x "$staged/node" "$staged/npm"
    make_stub "$1" "'$(command -v cp)' '$staged/node' '$staged/npm' '$SANDBOX_BIN/'"
}

run_install_fn() {
    run env -i HOME="$TEST_HOME" PATH="$SANDBOX_BIN" NO_COLOR=1 "$BASH" -c \
        'source "$1"; shift; "$@"' _ "$TEST_DIR/install_functions.bash" "$@"
}

@test "install.sh deps: Debian nodejs without npm is explained and never triggers root apt changes" {
    setup_dependency_sandbox
    make_stub node "$(node_stub_body 22)"
    make_stub sudo; make_stub apt-get; make_stub curl; make_stub wget

    run_install_fn install_oracle
    log_test_output "$output"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *'Node.js v22.1.0 is too old: Oracle needs Node.js 24+'* ]]
    [[ "$output" == *'installed without npm'* ]]
    [[ "$output" == *'setup_24.x'* && "$output" != *'setup_18.x'* ]]
    local calls
    calls=$(cat "$STUB_LOG")
    [[ "$calls" != *sudo* && "$calls" != *apt-get* && "$calls" != *curl* && "$calls" != *wget* ]]
}

@test "install.sh deps: a ready Node.js installs Oracle without touching package managers" {
    setup_dependency_sandbox
    make_stub node "$(node_stub_body 24)"
    make_stub npm; make_stub sudo; make_stub apt-get; make_stub pacman

    run_install_fn install_oracle
    log_test_output "$output"

    assert_success
    local calls
    calls=$(cat "$STUB_LOG")
    [[ "$calls" == *'npm install -g @steipete/oracle'* ]]
    [[ "$calls" != *sudo* && "$calls" != *pacman* && "$calls" != *apt-get* ]]
}

@test "install.sh deps: success is judged by the resulting node and npm, not the package manager's exit" {
    # pacman exits 0 but leaves a Node.js that is too old for Oracle.
    setup_dependency_sandbox old
    make_stub sudo '"$@"'
    installer_puts_node pacman 22
    run_install_fn install_node
    log_test_output "$output"
    [[ "$status" -ne 0 ]]
    [[ "$(cat "$STUB_LOG")" == *'pacman -S --needed --noconfirm nodejs npm'* ]]
    [[ "$output" == *'Could not set up Node.js 24+ with npm automatically'* ]]

    # The same flow with a current Node.js succeeds.
    setup_dependency_sandbox current
    make_stub sudo '"$@"'
    installer_puts_node pacman 25
    run_install_fn install_node
    log_test_output "$output"
    assert_success
    [[ "$output" == *'Node.js ready: v25.1.0'* ]]
}

@test "install.sh deps: points out the end-of-life NodeSource 18 feed older installers added" {
    setup_dependency_sandbox
    local list="$TEST_DIR/nodesource-18.list"
    printf '%s\n' 'deb [arch=amd64 signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_18.x nodistro main' > "$list"
    run_install_fn warn_legacy_nodesource_feed "$list"
    assert_success
    [[ "$output" == *'end-of-life Node.js 18 apt feed'* && "$output" == *'/etc/apt/preferences.d/nodejs'* ]]

    list="$TEST_DIR/nodesource-24.list"
    printf '%s\n' 'deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_24.x nodistro main' > "$list"
    run_install_fn warn_legacy_nodesource_feed "$list"
    assert_success
    [[ -z "$output" ]]

    # A release upgrade comments the entry out; a disabled feed is not reported.
    list="$TEST_DIR/nodesource-18-disabled.list"
    printf '%s\n' '# deb [arch=amd64 signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_18.x nodistro main # disabled on upgrade' > "$list"
    run_install_fn warn_legacy_nodesource_feed "$list"
    assert_success
    [[ -z "$output" ]]

    run_install_fn warn_legacy_nodesource_feed "$TEST_DIR/missing.list"
    assert_success
    [[ -z "$output" ]]
}

@test "install.sh deps: Debian without Node.js changes nothing and prints how to get Node 24+ with npm" {
    setup_dependency_sandbox
    make_stub sudo; make_stub apt-get; make_stub curl; make_stub wget

    run_install_fn install_oracle
    log_test_output "$output"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *'Node.js is not installed (Oracle needs Node.js 24+ with npm)'* ]]
    [[ "$output" == *'Not changing apt packages or sources automatically on Debian/Ubuntu'* ]]
    [[ "$output" == *'nvm, fnm or mise'* && "$output" == *'setup_24.x'* ]]
    [[ ! -s "$STUB_LOG" ]]
}

@test "install.sh deps: Debian Node.js 24+ without npm gets the npm package hint, not a too-old warning" {
    setup_dependency_sandbox
    make_stub node "$(node_stub_body 24)"
    make_stub sudo; make_stub apt-get

    run_install_fn install_node
    log_test_output "$output"

    [[ "$status" -ne 0 ]]
    [[ "$output" != *'too old'* ]]
    [[ "$output" == *'installed without npm'* ]]
    [[ "$output" == *'sudo apt-get install -y npm'* ]]
    local calls
    calls=$(cat "$STUB_LOG")
    [[ "$calls" != *sudo* && "$calls" != *apt-get* ]]
}

@test "install.sh deps: apt-get wins over pacman and dnf binaries installed on Debian/Ubuntu" {
    setup_dependency_sandbox
    make_stub sudo '"$@"'; make_stub apt-get
    installer_puts_node pacman 25
    installer_puts_node dnf 25

    run_install_fn install_node
    log_test_output "$output"

    [[ "$status" -ne 0 ]]
    [[ ! -s "$STUB_LOG" ]]
}

@test "install.sh deps: macOS installs Node.js with Homebrew and checks the result" {
    setup_dependency_sandbox mac Darwin
    make_stub sudo
    installer_puts_node brew 25

    run_install_fn install_node
    log_test_output "$output"

    assert_success
    [[ "$output" == *'Node.js ready: v25.1.0'* ]]
    [[ "$(cat "$STUB_LOG")" == 'brew install node' ]]
}
