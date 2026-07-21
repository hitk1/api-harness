## Contexto
O atual cenário, contempla um fluxo de multiplos estágios de construção do prompt que é enviado a API da LLM para gerar uma resposta pra usuário a cada iteração. Então temos a etapas de anexo de conhecimento de domínio, de sessão, dos objetivos do usuário e as últimas mensagens trocadas com o usuário também. Porém, como não existe um controle hoje de quantidade tokens dessa janela, isso pode ser um problema (estouro de quantidade de tokens). O controle de tokens (janela de contexto, por sessão), deve resolver este problema.


## Tarefa
Implementar um fluxo complementar de controle de quantidade de tokens que serão trafegados para cada interação do usuário com a LLM, a fins de mitigar o clássico problema de "só" ficar anexando contexto e mais dados nos prompts sem controle e uma hora perder o controle disso, gerando um bug sem ter noção do que possa ser. 

## Análise e Desenvolvimento
Preciso que seja feita uma análise sobre este problema, sobre qual a melhor forma de ser feito este controle. Preciso que isso seja registrado em algum lugar pois vou enviar isso ao frontend com o usuário para dar um feedback de como esta a janela de contexto atual a cada iteração.

## Fluxo de otimização/compactação da janela de contexto
A fim de otimizar a experiência do usuário, e quando uma sessão tem sua janela de contexto "estourando" os limites do modelo. Não querer forçar o usuário abandonar sua atual sessão, forçando-o a abrir uma nova sessão e perder todo o trabalho/contexto do que foi feito anteriormente. Para isso, preciso implementar uma estratégia de compactação que hoje é muito utilizada em vários modelos de harness. 

Para isso o fluxo deve ser autosuficiente e inteligente para detectar quando esta janela estiver estourando os limites (próximo do limite de tokens), que automaticamente inicie as funções de "compaction". É necessário que seja implementado estruturas de resiliência, neste caso, o ideal (na minha visão), seria a cada resposta devolvida aos clientes, que uma analise async seja feita do total de tokens da janela de contexto e se identificado que a sessão atual está extrapolando os limites do contexto, marcar esta sessão como "dirty" no caso um "needsCompaction: true" no registro dessa sessão no banco de dados. E então disparar as funções necessárias para fazer a compactação do contexto. Desta forma, se o sistema encontrar algum erro ou para durante a execução, seria possível na próxima inicialização, checar sessões flagadas como "needsCompaction" e refazer o processo.

## NeedsCompaction - flag & regras de negócio da feature.
Está feature deve ser capaz de identificar/controlar quais sessões estão flagadas e que são necessárias terem seus contextos compactados. O Mais importante é durante a execução do "compaction" de uma sessão. A interação com o usuário não sera permitida até que o compaction finalize.

### Estruturas principais do Compaction
Abaixo uma lista de estruturas/diretivas que o prompt deve seguir/explicitar ao iniciar o fluxo de compactação das mensagens:

- Pedido e Intenção Primária: Capture todos os pedidos e intenções explícitas do usuário em detalhe
- Conceitos Técnicos-Chave: Liste todos os conceitos técnicos, tecnologias e frameworks discutidos.
- Arquivos e Trechos de Código: Enumere arquivos e trechos específicos que foram examinados, modificados ou criados…
- Erros e correções: Liste todos os erros que apareceram e como foram corrigidos…
- Resolução de Problemas: Documente problemas resolvidos e investigações em andamento.
- Todas as mensagens do usuário: Liste TODAS as mensagens do usuário que não são resultados de ferramentas. São críticas…
- Tarefas Pendentes: Liste tarefas pendentes que foram explicitamente solicitadas.
- Trabalho Atual: Descreva em detalhe precisamente o que estava sendo feito imediatamente antes desse pedido de resumo…
- Próximo Passo Opcional: Liste o próximo passo que você vai tomar…

