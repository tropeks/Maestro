**empty-impl** — `NotImplementedError` / `todo!()` que sobrevive ao commit é
esqueleto vestido de produto: quem chama só descobre em runtime. Implemente
agora, ou remova a função e deixe o chamador falhar em compile/import — falha
cedo e visível vence promessa vazia.
