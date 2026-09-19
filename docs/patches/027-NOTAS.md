# Ordem 027 — sandbox de sabotagem também pergunta pelo endereço (2026-09-19)

Chegada: 2026-09-19T00:03:11-03:00.

## 1. O achado, confirmado

Com a 019 aplicada (guards religados por MECANISMO em `lib/`), dois testes
reprovavam:

```
test-order-issue11.sh          FAIL sabotagem não pegou (padrão do sed não bateu)
test-order-006-habits-debt.sh  FAIL sabotagem não pegou (padrão do sed não bateu)
```

Os dois blocos "terceiro estado" copiavam `$BIN` (`bin/maestro`) para uma
sandbox e sabotavam com `sed` um trecho que a ordem 016 (`36419c6`, E24) já
tinha movido:

| teste | trecho sabotado | morava | mora hoje |
|---|---|---|---|
| `issue11` | `if (( e_load > load_limiar ))` | `bin/maestro` | `lib/cmd-evidence.sh` (`_ev_cmd_qualifiers`) |
| `006-habits` | `now_epoch > vence && cur > alvo` | `bin/maestro` | `lib/cmd-habits.sh` (dentro de `cmd_habits`) |

O `sed` não achava o padrão em `$SAB` (a cópia de `bin/maestro`), o guard
`sabotagem não pegou` disparava honestamente — o andaime tinha apodrecido, a
asserção não.

## 2. O que mudou, e por quê

Nos dois arquivos, a sandbox passou a:

1. Criar `$SABROOT/lib/` além de `$SABROOT/bin/`.
2. **COPIAR** (nunca symlinkar) só os módulos `lib/` que o mecanismo sabotado
   realmente precisa — copiar o resto por symlink continuaria isolado (o
   binário sabotado não pode afetar o repo real), mas copiar o arquivo-alvo
   é o que permite sabotá-lo sem tocar o repo real.
3. Sabotar a CÓPIA do módulo `lib/`, não `$SAB` (que continua sendo uma cópia
   intacta de `bin/maestro` — ele só faz o `source` do módulo sabotado).

### issue11 (evidence)

`_ev_lib_load` exige `lib/core-evidence.sh` + `lib/cmd-evidence.sh`. Copiados
os dois. **Achado extra durante a depuração:** `_ev_cmd_verdict` chama
`_verif_lib_load` (`lib/cmd-verify.sh`) ANTES de medir a qualificação — sem
copiar esse terceiro módulo, o comando morria em "lib/cmd-verify.sh não
encontrado" e a asserção "reprovava" pelo motivo ERRADO (die env, não a
sabotagem) — o no-op mentindo na direção oposta, exatamente a armadilha que
a ordem avisou. Copiado também `lib/cmd-verify.sh` (ele por sua vez sourceia
`hooks/lib/verifications.sh` e `hooks/lib/common.sh`, ambos já alcançáveis
pelo symlink `hooks/` existente — nenhuma cópia adicional necessária).

### 006-habits-debt (habits)

`_habits_lib_load` exige só `lib/cmd-habits.sh`. Copiado esse único arquivo;
sem dependências adicionais de `lib/` (confirmado por grep antes de editar).

## 3. Prova de que não virou no-op

`bash -x` no binário sabotado, nos dois casos, mostra o `source` do módulo
`lib/` sabotado E a condição invertida executando de fato:

```
issue11:  + source .../sabotado/lib/cmd-evidence.sh
          ++ ((  e_load <= load_limiar  ))
006:      + source .../sabotado/lib/cmd-habits.sh
          + ((  now_epoch < vence && cur > alvo  ))
```

Sem as cópias corretas, o trace mostrava `die env "lib/cmd-verify.sh não
encontrado"` (issue11) — confirmando que o passo de depuração pegou o no-op
antes de ele virar falso-verde permanente.

## 4. As duas pontas

- **issue11**, íntegro: `evidência (carga): VÁLIDA, mas fora do limiar de
  medição (load 12.12)`. Sabotado: `evidência (carga): VÁLIDA (load 12.12)`
  — a MESMA asserção reprova.
- **006-habits**, íntegro: `run_habits` (vencida+acima do alvo) → exit 1.
  Sabotado: exit 0 — a MESMA asserção (rc==1) reprova.

## 5. Suíte e doctor

- Suíte completa (`tests/run-all.sh`) no worktree com a 019 + estas mudanças:
  **0 FAIL, SUITE OK**. Os dois FAIL de hoje somem; nenhum novo apareceu.
- Repetido em CÓPIA PATCHADA (`git clone` de `/tmp/wt-027` para
  `scratchpad/clone-check2`, arquivos dos 4 testes da 019 restaurados ao
  estado pós-019, os dois patches desta ordem aplicados via `git apply`, e
  confirmado BYTE-IDÊNTICO ao worktree antes de rodar): **0 FAIL, SUITE OK**.
- `maestro doctor`: veredito **inalterado** — "instalação saudável" antes e
  depois (contagem de checagens varia ±1 por causa do estado de push/tag do
  ambiente, não do meu patch — não toquei `bin/`, `lib/` nem `hooks/`).
- `maestro habits --all` nos dois arquivos editados: limpo (2 arquivo(s)
  sensoriado(s), exit 0).
- Recibo: `maestro evidence --record --label order-27 -- bash tests/run-all.sh`
  gravado (exit 0). Leitura: `VÁLIDA, mas fora do limiar de medição (load
  4.28)` — máquina carregada durante a rodada (load 1min ~4-6 observado ao
  longo da sessão); resultado do CONTEÚDO (SUITE OK, exit 0) não depende da
  carga, só a qualificação de latência do recibo fica marcada como
  inconclusiva sob carga.

## 6. O que NÃO mudou

- Nenhuma linha de `bin/`, `lib/` ou `hooks/` tocada.
- O que a asserção AFIRMA não mudou em nenhum dos dois testes — só o andaime
  (onde a sandbox busca o mecanismo, e qual arquivo o `sed` sabota) mudou.
- O guard `sabotagem não pegou` continua de pé nos dois arquivos.
- As mudanças da ordem 019 (comentários "Guard por MECANISMO" e os `grep -r`
  em `lib`/`bin`/`hooks`) não fazem parte do commit desta ordem — continuam
  como edição direta, não commitada, no worktree (o pacote final é
  responsabilidade do diretor).

## 7. Patches desta ordem

- `docs/patches/027-sandbox-minima-test-order-issue11.patch`
- `docs/patches/027-sandbox-minima-test-order-006-habits-debt.patch`

Gerados contra o estado COM a 019 aplicada (reconstruído a partir do
working tree, revertendo só as MINHAS edições) — `git apply --check` valida
limpo tanto contra esse estado quanto (por não haver overlap de linhas com
os hunks da 019 nestes dois arquivos) contra o HEAD nu; a aplicação real,
seguida da comparação byte a byte com o arquivo final do worktree, confirma
que o resultado é idêntico.
