## Contexto
Eu quero montar uma aplicação back end com elixir Que é uma API Que precisa ter um endpoint E que é responsável por receber uma interação do usuário Que é uma Mensagem através de um chat que eu vou disponibilizar Através de uma aplicação frontend.
A regra de negócio deste endpoint Deve ser responsável por Responder as dúvidas do usuário Relacionado ao domínio da aplicação que está voltado para a área jurídica . Então , na prática O usuário vai fazer perguntas sobre documentos que ele fez upload na aplicação E com isso deve ser capaz de responder as suas dúvidas. MAs o foco desses especificamente que deste endpoint, É ter uma engenharia focada em um agente da area jurídica. Objetivo dessa aplicação É se validar alguns conceitos e práticas de engenharia voltadas para esse agente inteligente com base em outros estudos feito observando o comportamento de outros agentes.

## Features
- A aplicação deve Exportar o módulo de usuário para fazer o crud e manutenção de novos usuários (quero poder usar o o REPL do elixir para fazer esse cadastramento)
- Ter um ednpoint para receber as mensagens do usuário e aplicar as técnicas de engenharia que serão discutidas mais à frente (esta feature deve contemplar a criação de sessões ou thread do usuário, ou seja, eu como usuário quero poder escolher em qual thread vou vou iteragir também - log devera ter um modulo de gestão dessas sessões, se precisar pode ser no mesmo formato do item anterior) 
- Atualizar constantemente os dados em banco de dados com base na interação dos usuários .

## Persistência de dados
Esta aplicação fará uso do postgres Como banco de dados e deve ser capaz de fazer a modelagem dos dados , seguindo O contexto da aplicação. Neste caso , Algumas tabelas de exemplo são:
- Tabela de usuários ;
- Tabela de mensagens ;
- Tabela de chats ;
- Tabela para atualização de Memória do contexto;
- Tabela fictícia para metadados de arquivos do usuário . 

( Dentre outras...) 

## Provedor de LLM
O provedor da inteligência artificial será a OPENAI , do qual a aplicação terá que fazer a integração com a api do serviço para ter acesso aos modelos de inteligência artificial.

### Modelo a ser utilizado
- GPT 4.0 mini

## Configurações e variáveis
A aplicação deve ser capaz de ler de um arquivo .env com todas as configurações de conexão com bancos de dados , chaves de apis e afins.


## Engenharia aplicada (harness engineering)
Arquitetura Do contexto da funcionalidade de inteligência artificial deve girar em volta Do seguinte contexto:
Eu preciso criar um Agent runtime, Do qual tenha um planner, coordinator, workers, memory system, tool registry, permissions, context builder e provedor de LLM (alguns modulos que podem fazer sentido para esta solução)

### Responsabilidade do "Agent runtime"
Este modulo é o coração do sistema . Ele deve ser responsável por executar loops de raciocínio , coordenar ferramentas , atualizar as memórias , construir contexto e orquestrar demais agentes, se for necessário.

### Planejamento deve ser separado da execução
Importante também é um modulo de planejamento , é a decisão mais importante que deve ser tomada e deve ser feito separado do modulo de execução . Então o modelo recomendado é o usuário faz uma interação ou módulo de planejamento faz de fato o planejamento , passa o plano de ação para o módulo executor para que então seja de fato atuado.

Exemplo: Quando o usuário solicita; "fala uma analise de todos os documentos enviados". o planejador ou modulo de planejamento deve ser capaz de identificar , analisar a solicitação do usuário e extrair ideias do tipo , identificar documentos , extrair conteúdo , classificar conteúdo , gerar relatório final 
Neste caso, o Modulo executou fica responsável por executa de fato os planejamento (passos idealizados na etapa anterior)

### Coordenador
O módulo coordenador pode existir e deve ser capaz de coordenar múltiplos workers Em paralelo.(pode ser feito em paralelo se necessário)**

Exemplo: Quando o usuário solicita: "analise todos os documentos deste contrato": O worker 1 deve ser capaz de ler um arquivo de contrato , o worker 2 deve ser capaz de ler Oo documento que contém as informações do cliente , o worker 3 deve ser capaz de ler o documento que contém as informações da empresa, e assim por diante.

### Sistemas de ferramentas 
O sistema de ferramentas é o módulo em que toda a ação do agente deve ocorrer através dessas ferramentas . Exemplo , ler 1 novo documento , escrever  um novo documento , buscar por entidades , gerar um relatório , executar um fluxo de trabalho.

### Sistemas de memória
Extremamente importante para aumentar o conhecimento do modelo e priorizar informações relevantes ao invés de documento e contexto bruto . O conceito é Memória não é histórico , Memória é conhecimento . 

#### Tipos de memória
#### Memória de sessão
Exceção representa o estado atual da tarefa .  Ou seja , são insights e fatos , anotações em que AEA pode extrair de interações do usuário como documento atual sendo trabalhado . A vigência do contrato , o valor da multa , o nome do cliente, etc; Geralmente é estruturado como JSON.
Serve o único e exclusivamente para a tarefa atual . No caso dessa aplicação do chat em vigência que o usuário esta interagindo, ou seja, se o usuário trocar para um novo chat, uma nova memoria de sessão deve ser criada e administrada

#### Memória persistente
A memória persistente representa um conhecimento útil para tarefas futuras.Está sempre atrelado ao usuário logado (vinculo)
Exemplo: "area de atuação": "área jurídica trabalhista"

OBSERVAÇÔES IMPORTANTES: Os grandes erros sobre qual é a persistente É assumir que tudo será anexado . O resultado vai ser ruído.
O correto é sempre persistir conhecimento duradouro . Uma pergunta para fazer essa validação é esse conhecimento vai ser útil daqui 30 dias ou mais , se não , não persistir 

#### Categorias de memória persistente
1 -> Memória de usuário: Deve garantir as preferências e comportamentos percebidos pelo modelo de inteligência artificial através das interações dos usuários . 
2 -> Conhecimento sobre uma tarefa: Eduardo está trabalhando em uma tarefa que envolve um contexto específico , por exemplo: Criando um novo processo para defender um cliente de uma ação trabalhista. Essa memória , então , deve ser capaz de trazer conhecimento sobre essa tarefa ou sobre esse trabalho desse contexto específico com base nas interações dos usuários 
3 -> Conhecimento de domínio:Essa memória é responsável por extrair conhecimento através das interações do usuário ao que diz respeito aos comportamentos e preferencias do usuário com base no propósito. Exemplo: Um agente voltado para área jurídica (como o caso desta aplicação): Deve-se capaz de detectar o tom do usuário de perfil/modo de trabalho dele em relação a várias áreas como: Direito do trabalho, direito da familia, etc;

REGRAS IMPORTANTES: 
- Gerenciamento de memória: Não deve ser usada a abordagem de append-only, ou seja, memoria persistente não deve ser log. Exemplo: Contexto de trabalho do usuário deve mudar sazonalmente Por isso , ficar só anexando novos conhecimentos nas demais categorias de memória não é uma boa ideia. Ao invés disso , a memória deve ser gerenciada como um exemplo de objetivo atual , por exemplo . Atualmente , o usuário está trabalhando num processo trabalhista . E em alguns dias , esse contexto deve mudar e ele pode trabalhar em um processo da área de direito da família , por exemplo . Na prática , a atualização de Memória deve ser feita sempre atualizando estados antigos . 

### Reconciliação de memória
Este componente é responsável por atualizar , mesclar , descartar e criar novos conhecimentos da memória com base em novas interações dos usuários.
O fluxo funciona da seguinte forma , uma nova interação passa por extração de fatos , análise de fatos candidatos (a ir pra memória), reconciliador de memória que de fato faz a criação , a atualização ou descarte de uma nova.

### Extração de conhecimento
A função de extração de conhecimento deve acontecer a cada interação dos usuários após uma conversa ou uma nova mensagem , o fluxo deve passar pelo extrator de conhecimento , gerar um conhecimento estruturado , geralmente feito em JSON . Então , passado para o reconciliador para a decisão . Exemplo: Preferencias, Objetivos, Restrições e fatos

### Context Builder (construtor de contexto)
o Prompt que vai para o modelo de inteligência artificial não deve ser composto apenas pelo histórico das das últimas mensagens do usuário . A estrutura recomendada é: Instrução de sistema, Contexto do domínio (preferencias e anotações gerais sobre domínio - no caso relacionado a area juridica), mémoria de sessão (insights e fatos,  estado atual da tarefa), Memoria persistente (conhecimento relevante para a interação atual), ultimas mensagens trocadas entre o usuário e o modelo e por fim, a pergunta do usuário (interação atual)

#### Memory retrieval (busca de memoria relevante)
Não deve ser feito , trazendo todos os dados de memória armazenados até então . O correto é fazer o entendimento da tarefa , fazer uma busca na memória para trazer conteúdos relevantes . Tudo isso de acordo com a interação do usuário.
Exemplo: Novo caso de funcionário demitido indevidamente -> Retrieval tras dados relacionados a isso ao invés de trazer tudo da memoria (filtro) e ignora as demais memorias relacionadas a experiência previa do usuário com direito da familia por exemplo

## Pipeline de atualização das memorias
o fluxo de atualização das memórias deve acontecer sempre ao responder ao usuário . Então deve ser feito uma extração de conhecimento com base na resposta gerada (proveniente da interação com a LLM). Após a extração do conhecimento , o fluxo deve passar por um processo de classificação de memória (reconcialiador), onde vai separar o que é memória de sessão , memória de usuário , memória de domínio , memória de projeto , etc . E após isso é enviado a um módulo de persistência . 

IMPORTANTE: Esse fluxo deve ser assincrono do processo principal, NÃO DEVE TRAVAR A RESPOSTA AO USUÁRIO (modelar um novo processo para fazer isso com Gen server - pensar que isso pode escalar, eu posso ter N usuário interagindo na minha API, isso de modo algum pode ser gargalo ou ocorrer percas de mensagens entre os processos do Elixir para as demais tarefas)

## Separa conversa de conhecimento
Importante para estruturar o processo de inteligência do modelo . Este é provavelmente o conceito mais importante . A conversa é efêmera , o conhecimento é duradouro Cada interação deve gerar 2 produtos . O primeiro é a resposta para o usuário e o segundo é o conhecimento estruturado . 

### Modelo a se manter em mente
o sistema não deve lembrar de tudo o sistema deve manter a melhor representação possível do que sabe atualmente . Portanto: Cada nova interação deve se extrair o conhecimento , comparar com o conhecimento existente através do reconciliador de memória para decidir se vai atualizar , mesclar , descartar ou criar uma nova memória e não a cada nova interação , simplesmente sai anexando . Fatos e conhecimento extraído dessa nova interação.