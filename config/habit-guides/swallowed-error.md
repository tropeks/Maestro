**swallowed-error** — `except: pass` / `catch {}` transforma um bug com stack
trace num bug silencioso que aparece longe da causa. Se o erro é esperado,
capture o TIPO específico e trate de verdade; se não é, deixe subir. Logar e
re-lançar é tratamento; engolir nunca é. `except:` sem tipo pega até
SystemExit/KeyboardInterrupt — nomeie a exceção esperada. Não faça: trocar por `log.debug` e
seguir — é o mesmo silêncio com perfume.
