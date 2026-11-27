#!/bin/bash
# Checks run inside the second sandbox layer (aspire-inner) on the Google Cloud machine: what is
# hidden, what is read-only, what still works. Run from the host as
#   ~/aspire-setup/aspire-sandbox.sh /run/aspire/aspire-inner 'bash ~/inner-tests.sh'
# (this file lives in the private home, ~/aspire-home/inner-tests.sh on the host).
echo "== hidden login"
echo "files in ~/.claude: $(ls -A ~/.claude | wc -l)"
echo "bytes in ~/.claude.json: $(wc -c < ~/.claude.json 2>/dev/null || echo absent)"
cat ~/.claude/.credentials.json 2>&1 | head -1
echo "== processes visible: $(ls /proc | grep -c '^[0-9]')"
echo "== writes that must fail"
for f in ~/.bashrc ~/.local/bin/claude ~/.config/inner-test ~/ASPIRE/.git/config ~/ASPIRE/.git/hooks/pre-commit ~/ASPIRE/.claude/settings.json ~/ASPIRE/.claude/settings.local.json; do
  if ( : >> "$f" ) 2>/dev/null; then echo "  WRITABLE (unexpected): $f"; else echo "  read-only: $f"; fi
done
echo "== writes that must work"
for d in ~/ASPIRE ~/.cache /tmp; do
  if f=$(mktemp -p "$d" inner-write-test.XXXX 2>/dev/null); then rm -f "$f"; echo "  writable: $d"; else echo "  NOT WRITABLE (unexpected): $d"; fi
done
echo "== GPU"; nvidia-smi -L
echo "== git"; git -C ~/ASPIRE log --oneline -1; git -C ~/ASPIRE status --short | head -5
echo "== hidden from both layers"; ls ~/.ssh 2>&1 | head -1; ls /home/nick/aspire-setup 2>&1 | head -1
