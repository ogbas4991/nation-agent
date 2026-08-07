---
name: nation-agent-tools
description: Complete reference for all NATION AGENT tool modules. Use when the agent needs to perform file operations, shell commands, git, search, Python execution, SQLite, HTTP, browser, Docker, SSH, or REST API tasks. Load this skill to know which tool to call and how.
---

# NATION AGENT — Tool Skills Reference

All tool scripts live in `~/.kiro/tools/`. Run any with `help` for full usage.

---

## 1. File Operations — `nation-file.sh`

Use for: reading, writing, copying, moving, finding, and inspecting files.

```bash
~/.kiro/tools/nation-file.sh read <path>
~/.kiro/tools/nation-file.sh write <path> "<content>"
~/.kiro/tools/nation-file.sh append <path> "<content>"
~/.kiro/tools/nation-file.sh delete <path> --confirm
~/.kiro/tools/nation-file.sh copy <src> <dst>
~/.kiro/tools/nation-file.sh move <src> <dst>
~/.kiro/tools/nation-file.sh list <dir>
~/.kiro/tools/nation-file.sh tree <dir> [depth]
~/.kiro/tools/nation-file.sh find <dir> <pattern>
~/.kiro/tools/nation-file.sh info <path>
~/.kiro/tools/nation-file.sh mkdir <path>
~/.kiro/tools/nation-file.sh exists <path>
~/.kiro/tools/nation-file.sh diff <file1> <file2>
~/.kiro/tools/nation-file.sh head <path> [lines]
~/.kiro/tools/nation-file.sh tail <path> [lines]
~/.kiro/tools/nation-file.sh grep <pattern> <path>
~/.kiro/tools/nation-file.sh wc <path>
~/.kiro/tools/nation-file.sh chmod <mode> <path>
```

**Safety**: `delete` requires `--confirm`. Never deletes recursively without explicit flag.

---

## 2. Shell Execution — `nation-shell.sh`

Use for: running commands, background processes, piping, timeouts.

```bash
~/.kiro/tools/nation-shell.sh run <cmd>
~/.kiro/tools/nation-shell.sh bg <cmd>
~/.kiro/tools/nation-shell.sh script <file.sh>
~/.kiro/tools/nation-shell.sh env
~/.kiro/tools/nation-shell.sh which <binary>
~/.kiro/tools/nation-shell.sh ps
~/.kiro/tools/nation-shell.sh kill <pid> [signal]
~/.kiro/tools/nation-shell.sh timeout <secs> <cmd>
~/.kiro/tools/nation-shell.sh pipe "<cmd1>" --- "<cmd2>"
```

**Safety**: Built-in block list prevents `rm -rf /`, `dd if=`, `git push --force`, etc.

---

## 3. Git — `nation-git.sh`

Use for: all git operations. Always run inside a git repo directory.

```bash
~/.kiro/tools/nation-git.sh status
~/.kiro/tools/nation-git.sh log [n] [path]
~/.kiro/tools/nation-git.sh diff [ref] [file]
~/.kiro/tools/nation-git.sh staged
~/.kiro/tools/nation-git.sh add <path...>
~/.kiro/tools/nation-git.sh commit "<message>"
~/.kiro/tools/nation-git.sh branch [name] [base]
~/.kiro/tools/nation-git.sh checkout <ref>
~/.kiro/tools/nation-git.sh stash [pop|list|show]
~/.kiro/tools/nation-git.sh pull [remote] [branch]
~/.kiro/tools/nation-git.sh push [remote] [branch]
~/.kiro/tools/nation-git.sh clone <url> [dir]
~/.kiro/tools/nation-git.sh blame <file> [start] [end]
~/.kiro/tools/nation-git.sh show <ref>
~/.kiro/tools/nation-git.sh reset <file>
~/.kiro/tools/nation-git.sh init [path]
~/.kiro/tools/nation-git.sh ignore <pattern>
```

**Safety**: `push --force` is blocked. Never amends pushed commits.

---

## 4. Search — `nation-search.sh`

Use for: finding code, patterns, files, TODOs, duplicates.

```bash
~/.kiro/tools/nation-search.sh text <pattern> <path>
~/.kiro/tools/nation-search.sh files <pattern> [path]
~/.kiro/tools/nation-search.sh type <ext> [path]
~/.kiro/tools/nation-search.sh large [path] [min_size]
~/.kiro/tools/nation-search.sh recent [path] [days]
~/.kiro/tools/nation-search.sh dupes [path]
~/.kiro/tools/nation-search.sh replace <pattern> <replace> <path>   # dry-run
~/.kiro/tools/nation-search.sh apply <pattern> <replace> <path>     # apply
~/.kiro/tools/nation-search.sh context <pattern> <path> [n]
~/.kiro/tools/nation-search.sh count <pattern> <path>
~/.kiro/tools/nation-search.sh todo [path]
```

---

## 5. Python Execution — `nation-python.sh`

Use for: running scripts, executing inline code, managing packages, virtual envs.

```bash
~/.kiro/tools/nation-python.sh run <file.py> [args...]
~/.kiro/tools/nation-python.sh exec "<code>"
~/.kiro/tools/nation-python.sh pip install <pkg...>
~/.kiro/tools/nation-python.sh pip list
~/.kiro/tools/nation-python.sh pip show <pkg>
~/.kiro/tools/nation-python.sh venv create <path>
~/.kiro/tools/nation-python.sh venv activate <path>
~/.kiro/tools/nation-python.sh check <file.py>
~/.kiro/tools/nation-python.sh lint <file.py>
~/.kiro/tools/nation-python.sh format <file.py>
~/.kiro/tools/nation-python.sh version
~/.kiro/tools/nation-python.sh env
```

---

## 6. SQLite — `nation-sqlite.sh`

Use for: all local database operations. Falls back to Python's sqlite3 if binary not installed.

```bash
~/.kiro/tools/nation-sqlite.sh query <db> "<sql>"
~/.kiro/tools/nation-sqlite.sh exec <db> "<sql>"
~/.kiro/tools/nation-sqlite.sh file <db> <sql_file>
~/.kiro/tools/nation-sqlite.sh tables <db>
~/.kiro/tools/nation-sqlite.sh schema <db> [table]
~/.kiro/tools/nation-sqlite.sh import <db> <table> <csv>
~/.kiro/tools/nation-sqlite.sh export <db> <table> <csv>
~/.kiro/tools/nation-sqlite.sh dump <db> [output.sql]
~/.kiro/tools/nation-sqlite.sh info <db>
~/.kiro/tools/nation-sqlite.sh create <db>
~/.kiro/tools/nation-sqlite.sh vacuum <db>
~/.kiro/tools/nation-sqlite.sh backup <db> <dest>
```

---

## 7. Browser / Web — `nation-browser.sh`

Use for: fetching web pages, extracting text, searching the web, checking URLs.

```bash
~/.kiro/tools/nation-browser.sh fetch <url>
~/.kiro/tools/nation-browser.sh html <url>
~/.kiro/tools/nation-browser.sh links <url>
~/.kiro/tools/nation-browser.sh title <url>
~/.kiro/tools/nation-browser.sh headers <url>
~/.kiro/tools/nation-browser.sh save <url> <file>
~/.kiro/tools/nation-browser.sh json <url>
~/.kiro/tools/nation-browser.sh search "<query>"
~/.kiro/tools/nation-browser.sh status <url>
```

---

## 8. HTTP — `nation-http.sh`

Use for: making HTTP requests to any endpoint.

```bash
~/.kiro/tools/nation-http.sh get <url> ["Header: Value"...]
~/.kiro/tools/nation-http.sh post <url> '<json_body>' ["Header: Value"...]
~/.kiro/tools/nation-http.sh put <url> '<json_body>'
~/.kiro/tools/nation-http.sh patch <url> '<json_body>'
~/.kiro/tools/nation-http.sh delete <url>
~/.kiro/tools/nation-http.sh head <url>
~/.kiro/tools/nation-http.sh upload <url> <file> [field]
~/.kiro/tools/nation-http.sh download <url> <file>
```

Body can be a JSON string or `@filename` to read from file.

---

## 9. Docker — `nation-docker.sh`

Use for: container management. Requires Docker daemon running.

```bash
~/.kiro/tools/nation-docker.sh ps [--all]
~/.kiro/tools/nation-docker.sh images
~/.kiro/tools/nation-docker.sh run <image> [cmd...]
~/.kiro/tools/nation-docker.sh exec <container> <cmd...>
~/.kiro/tools/nation-docker.sh logs <container> [--tail n]
~/.kiro/tools/nation-docker.sh stop <container>
~/.kiro/tools/nation-docker.sh rm <container> [--force]
~/.kiro/tools/nation-docker.sh build [path] [tag]
~/.kiro/tools/nation-docker.sh pull <image>
~/.kiro/tools/nation-docker.sh inspect <container|image>
~/.kiro/tools/nation-docker.sh stats [container]
~/.kiro/tools/nation-docker.sh compose <up|down|ps|logs>
~/.kiro/tools/nation-docker.sh prune --confirm
```

If Docker is not installed, the tool will say so clearly with install instructions.

---

## 10. SSH — `nation-ssh.sh`

Use for: remote connections, file transfers, tunnels, key management.

```bash
~/.kiro/tools/nation-ssh.sh connect <host> [user] [port]
~/.kiro/tools/nation-ssh.sh run <host> "<cmd>" [user] [port]
~/.kiro/tools/nation-ssh.sh copy-to <host> <local> <remote> [user] [port]
~/.kiro/tools/nation-ssh.sh copy-from <host> <remote> <local> [user] [port]
~/.kiro/tools/nation-ssh.sh tunnel <host> <local_port> <remote_port> [user]
~/.kiro/tools/nation-ssh.sh keygen [name] [type]
~/.kiro/tools/nation-ssh.sh keys
~/.kiro/tools/nation-ssh.sh config [host]
~/.kiro/tools/nation-ssh.sh test <host> [user] [port]
~/.kiro/tools/nation-ssh.sh add-host <alias> <hostname> [user] [port]
```

---

## 11. REST APIs — `nation-rest.sh`

Use for: calling REST APIs, auth, mocking, testing, JWT, OpenAPI.

```bash
~/.kiro/tools/nation-rest.sh call <METHOD> <url> [body]
~/.kiro/tools/nation-rest.sh auth basic <url> <user> <pass>
~/.kiro/tools/nation-rest.sh auth bearer <url> <token>
~/.kiro/tools/nation-rest.sh auth apikey <url> <key> [header]
~/.kiro/tools/nation-rest.sh mock <port> [responses.json]
~/.kiro/tools/nation-rest.sh test <spec_file>
~/.kiro/tools/nation-rest.sh encode "<string>"
~/.kiro/tools/nation-rest.sh decode "<string>"
~/.kiro/tools/nation-rest.sh jwt decode <token>
~/.kiro/tools/nation-rest.sh jwt encode '<payload_json>' <secret>
~/.kiro/tools/nation-rest.sh openapi <url_or_file>
~/.kiro/tools/nation-rest.sh ping <base_url>
```

---

## Error Recovery Patterns

When a tool fails:
1. Check the error message — it always says what went wrong
2. Check `~/.kiro/logs/nation-agent.log` for the full trace
3. Run `~/.kiro/tools/nation-heal.sh diagnose <tool> <error>` for auto-diagnosis
4. Common fixes:
   - Missing binary → tool will print install command (e.g. `pkg install sqlite`)
   - Permission denied → `chmod +x <script>`
   - Not in git repo → `cd` to the project directory first
   - Network error → check connectivity with `nation-browser.sh status <url>`

## Memory System

Conversation memory is stored in `~/.kiro/memory/`:
- `memory.db` — SQLite database of all past interactions
- Use `~/.kiro/tools/nation-memory.sh recall <topic>` to retrieve past context
- Memory is auto-loaded at agent spawn via the agentSpawn hook
