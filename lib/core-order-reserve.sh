#!/usr/bin/env bash
# maestro lib/core-order-reserve.sh — ordem 049 (INTENT v56, "a linha de produção").
#
# Numeração de ordens por RESERVA no ledger. `order --create` numerava pelo
# que havia em `.maestro/orders/` da árvore onde rodava: ordem que existia só
# em branch ou em outro worktree era invisível (a 070 e a 072 colidiram no
# ponte-daemon; a 006 saiu duplicada no Enterprise).
#
# O número novo é o maior entre (a) a árvore, (b) todos os worktrees do repo,
# (c) todos os branches locais e remotos e (d) as reservas ainda válidas em
# `~/.maestro/order-state/reserva/` — e a reserva é gravada SOB LOCK ATÔMICO
# (mkdir) antes de a ordem existir como arquivo. Duas criações simultâneas
# serializam no lock: nunca recebem o mesmo número.
#
# Reserva que ninguém consumiu (ordem nunca commitada) tem validade EXPLÍCITA
# (`expires_at`, MAESTRO_ORDER_RESERVE_TTL em segundos, padrão 7 dias): vencida,
# deixa de segurar o número, mas `--list` a MOSTRA como expirada — nunca some
# em silêncio. Sem mudança no formato do arquivo da ordem nem do carimbo.
#
# Sourced sob demanda por lib/cmd-order.sh (`_order_reserve_lib_load`);
# `die`, `maestro_now_epoch`, `maestro_brief_file` e `_order_state_field`
# (core-order-terminal.sh) já no escopo.
_order_reserve_dir() { printf '%s/order-state/reserva' "${MAESTRO_HOME:-$HOME/.maestro}"; }
_order_reserve_base() { # <proj> → chave do projeto (a mesma do registro terminal; worktree e repo principal dão a mesma)
  local bf; bf=$(maestro_brief_file "$1"); bf="${bf##*/}"; printf '%s' "${bf%.md}"
}
_order_reserve_ttl() {
  local t="${MAESTRO_ORDER_RESERVE_TTL:-604800}"
  [[ "$t" =~ ^[0-9]{1,9}$ ]] || t=604800
  printf '%s' "$t"
}
_order_reserve_max_names() { # lê nomes de arquivo em stdin → maior NNN inicial (0 se nenhum)
  local n m=0
  while IFS= read -r n; do
    n="${n##*/}"
    [[ "$n" =~ ^([0-9]{3})([-.]|$) ]] || continue
    (( 10#${BASH_REMATCH[1]} > m )) && m=$(( 10#${BASH_REMATCH[1]} ))
  done
  printf '%s' "$m"
}
_order_reserve_max_git() { # <proj> → maior NNN em worktrees, branches locais e remotos (git ausente ⇒ 0)
  local proj="$1" m=0 v p ref
  git -C "$proj" rev-parse --git-dir >/dev/null 2>&1 || { printf '0'; return 0; }
  while IFS= read -r p; do   # (b) todos os worktrees do repo
    [[ -d "$p/.maestro/orders" ]] || continue
    v=$(ls "$p/.maestro/orders" 2>/dev/null | _order_reserve_max_names)
    (( v > m )) && m=$v
  done < <(git -C "$proj" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')
  while IFS= read -r ref; do   # (c) branches locais e remotos
    v=$(git -C "$proj" ls-tree -r --name-only "$ref" -- .maestro/orders 2>/dev/null | _order_reserve_max_names)
    (( v > m )) && m=$v
  done < <(git -C "$proj" for-each-ref --format='%(refname)' refs/heads refs/remotes 2>/dev/null)
  printf '%s' "$m"
}
_order_reserve_max_reserved() { # <base> <agora> → maior NNN entre reservas AINDA VÁLIDAS
  local base="$1" now="$2" rd f m=0 n exp
  rd=$(_order_reserve_dir)
  for f in "$rd/$base"-[0-9][0-9][0-9]; do
    [[ -f "$f" ]] || continue
    exp=$(_order_state_field "$f" expires_at)
    [[ "$exp" =~ ^[0-9]+$ ]] && (( exp > now )) || continue
    n="${f##*-}"
    (( 10#$n > m )) && m=$(( 10#$n ))
  done
  printf '%s' "$m"
}
_order_reserve_lock() { # <lockdir> — mkdir atômico; lock órfão (>30 s) é tomado
  local lk="$1" tries=0 mt now
  while ! mkdir "$lk" 2>/dev/null; do
    mt=$(stat -c %Y "$lk" 2>/dev/null || echo 0)
    now=$(maestro_now_epoch)
    (( mt > 0 && now - mt > 30 )) && { rmdir "$lk" 2>/dev/null; continue; }
    (( ++tries > 400 )) && return 1
    sleep 0.05
  done
}
_order_reserve_next() { # <proj> → NNN reservado em stdout; die env (rc 2) se não consegue o lock/gravar
  local proj="$1" base rd lk now max v oid rf tmp
  base=$(_order_reserve_base "$proj"); rd=$(_order_reserve_dir); lk="$rd/$base.lock"
  mkdir -p "$rd" 2>/dev/null || die env "não consigo criar $rd" "cheque permissões de ~/.maestro" 2
  _order_reserve_lock "$lk" || die env "lock de numeração de ordens ocupado ($lk)" \
    "outra criação está travada; se não houver nenhuma rodando, remova $lk" 2
  now=$(maestro_now_epoch)
  max=$(ls "$proj/.maestro/orders" 2>/dev/null | _order_reserve_max_names)   # (a) a árvore
  v=$(_order_reserve_max_git "$proj");              (( v > max )) && max=$v
  v=$(_order_reserve_max_reserved "$base" "$now");  (( v > max )) && max=$v   # (d)
  oid=$(printf '%03d' "$(( max + 1 ))")
  rf="$rd/$base-$oid"; tmp="$rf.tmp.$$"
  { printf 'schema=maestro-order-reserve-v1\nid=%s\nreserved_at=%s\nexpires_at=%s\n' \
      "$oid" "$now" "$(( now + $(_order_reserve_ttl) ))"; } > "$tmp" && mv -f "$tmp" "$rf" \
    || { rm -f "$tmp" 2>/dev/null; rmdir "$lk" 2>/dev/null; die env "falha ao gravar a reserva $rf" "" 2; }
  rmdir "$lk" 2>/dev/null
  printf '%s' "$oid"
}
_order_reserve_list() { # <proj> <odir> → uma linha por reserva SEM ordem na árvore (ativa ou expirada)
  local proj="$1" odir="$2" base rd f n exp now st
  base=$(_order_reserve_base "$proj"); rd=$(_order_reserve_dir); now=$(maestro_now_epoch)
  for f in "$rd/$base"-[0-9][0-9][0-9]; do
    [[ -f "$f" ]] || continue
    n="${f##*-}"
    compgen -G "$odir/$n-*.md" >/dev/null 2>&1 && continue
    compgen -G "$odir/$n.md" >/dev/null 2>&1 && continue   # consumida
    exp=$(_order_state_field "$f" expires_at)
    if [[ "$exp" =~ ^[0-9]+$ ]] && (( exp > now )); then st="reservada até $(date -d "@$exp" -Iseconds 2>/dev/null || echo "$exp")"
    else st="EXPIRADA em $(date -d "@${exp:-0}" -Iseconds 2>/dev/null || echo "${exp:-?}") — número liberado"; fi
    printf '%s  [reserva: %s]  (ordem não commitada; arquivo de reserva em %s)\n' "$n" "$st" "$f"
  done
}
