Especificação - Context Runtime e Gerenciamento de Budget de Tokens
Objetivo

O sistema não deve construir prompts através da concatenação direta de informações.

Ao invés disso, deve existir um Context Runtime, responsável por orquestrar toda a construção do contexto enviado para a LLM.

O Runtime deve tratar a janela de contexto como um recurso limitado (budget), distribuindo esse orçamento entre diferentes provedores de informação (Providers).

O objetivo é garantir:

utilização previsível da janela de contexto;
custo constante por interação;
baixa latência;
possibilidade de sessões praticamente infinitas;
facilidade de adicionar novos tipos de memória futuramente.
Princípios
O contexto nunca é armazenado

O banco de dados nunca deve armazenar um "prompt pronto".

O banco armazena apenas as fontes de informação.

O contexto é reconstruído dinamicamente a cada interação.

O contexto é composto por Providers

Cada origem de informação é representada por um Provider independente.

Exemplo:

SystemPromptProvider

PersistentMemoryProvider

SessionMemoryProvider

ConversationProvider

UserActionProvider

ToolProvider

RAGProvider

ExecutionPlanProvider

Cada Provider possui responsabilidade única.

Ele sabe apenas:

localizar dados
selecionar dados
resumir dados quando necessário

Ele nunca decide sozinho quanto espaço irá ocupar.

Context Runtime

O Context Runtime é responsável por:

calcular orçamento disponível
distribuir budgets
solicitar informações aos providers
montar o prompt final
validar limite de tokens

Ele é o único componente que conhece o tamanho máximo da janela.

                Request
                    │
                    ▼
            Context Runtime
                    │
     ┌──────────────┼──────────────┐
     ▼              ▼              ▼
 Providers     BudgetManager   TokenCounter
     │              │              │
     └──────────────┴──────────────┘
                    │
                    ▼
             Prompt Assembly
                    │
                    ▼
                  LLM
Budget Manager

O Budget Manager controla toda a distribuição da janela.

Nunca existe montagem de contexto sem budget.

Exemplo:

Janela disponível

200000 tokens

Reserva inicial:

Output

15000

Reserva:

Ferramentas

5000

Reserva:

Sistema

4000

Resultado:

Budget restante

176000

Este orçamento será distribuído entre os Providers.

Cada Provider recebe um orçamento

O Provider nunca devolve informação ilimitada.

Exemplo:

PersistentMemoryProvider

Budget recebido:

12000 tokens

Ele deve decidir:

quais memórias utilizar
qual versão utilizar
se deve resumir

Nunca ultrapassando o orçamento recebido.

Providers devem suportar múltiplos níveis de detalhe

Todo Provider deve ser capaz de produzir versões diferentes do mesmo conteúdo.

Exemplo:

FULL

12000 tokens
SUMMARY

4000 tokens
ESSENTIAL

1200 tokens

O Runtime escolhe qual utilizar.

Budget Hierárquico

O orçamento deve ser distribuído em níveis.

Exemplo:

Janela

↓

Output Reserve

↓

System Prompt

↓

Tool Definitions

↓

Execution Plan

↓

Persistent Memory

↓

Session Memory

↓

Conversation

↓

Current User Message

Nenhum componente pode consumir orçamento reservado para outro.

Token Counter

Todo texto persistido deve possuir contagem de tokens previamente calculada.

Nunca recalcular durante uma requisição.

Exemplo:

Memory

id

content

token_count

summary_token_count

importance

created_at

updated_at

O mesmo vale para:

mensagens
fatos
resumos
documentos
ações
Importance Score

Todo elemento armazenado deve possuir um indicador de importância.

Exemplo:

importance

0.0

até

1.0

Exemplos:

"ok"

0.05
"Obrigado"

0.05
"O usuário prefere UUIDv7"

0.95

Durante reduções de contexto:

informações menos importantes desaparecem primeiro.

Session Runtime

Cada sessão deve possuir métricas.

Exemplo:

Session

current_tokens

rolling_summary_tokens

message_tokens

memory_tokens

last_compaction

compaction_count

Isso evita reconstruções completas apenas para descobrir o tamanho da sessão.

Estados da Sessão

A sessão deve possuir estados.

ACTIVE

↓

NEEDS_COMPACTION

↓

COMPACTING

↓

READY

Após cada interação:

Nova mensagem

↓

Atualiza métricas

↓

Passou do limite?

↓

Sim

↓

Marca NEEDS_COMPACTION

O compaction pode ocorrer de forma assíncrona.

Rolling Summary

O resumo da sessão nunca substitui completamente as mensagens.

Sempre existe:

Rolling Summary

+

Mensagens recentes

Exemplo:

Resumo

2500 tokens

+

Últimos

12000 tokens
Session Memory

Memória de sessão não deve existir apenas como um bloco de texto.

Ela deve ser organizada em níveis.

Exemplo:

Messages

↓

Facts

↓

Episodes

↓

Rolling Summary

Onde:

Messages

Histórico completo.

Facts

Informações permanentes descobertas durante a conversa.

Exemplo:

Usuário prefere Elixir.

Projeto utiliza Postgres.

Objetivo atual é construir um Harness.
Episodes

Resumo de grupos de mensagens.

Exemplo:

Discussão sobre autenticação.

Discussão sobre RAG.

Discussão sobre agentes.
Rolling Summary

Resumo consolidado de toda a sessão.

Context Assembly

A construção do contexto deve seguir prioridade.

Exemplo:

System Prompt

↓

Execution Plan

↓

Persistent Memory

↓

Session Facts

↓

Session Episodes

↓

Rolling Summary

↓

Recent Messages

↓

Current User Message

Caso o orçamento seja insuficiente:

reduzir detalhes
utilizar versões resumidas
remover componentes menos prioritários

Nunca ultrapassar o limite.

Providers não conhecem a janela

Providers nunca devem conhecer:

tamanho da janela
limite do modelo
orçamento global

Recebem apenas:

Budget

12000 tokens

e retornam conteúdo compatível.

Planejamento antes da montagem

A montagem ocorre em duas fases.

Planejamento

Cada Provider informa:

tamanho disponível
versões existentes
custo estimado

Exemplo:

Persistent Memory

FULL

15000

SUMMARY

5000

ESSENTIAL

1200
Montagem

O Runtime distribui o orçamento e escolhe qual versão utilizar.

Somente então o prompt é montado.

Pós-processamento

Após cada resposta da LLM:

Salvar mensagens

↓

Atualizar métricas

↓

Extrair fatos

↓

Atualizar memória

↓

Atualizar episódios

↓

Verificar budget

↓

Agendar compaction se necessário

O compaction nunca ocorre durante a geração da resposta.

Sempre após a interação.

Objetivo arquitetural

Todo o sistema deve tratar contexto como um recurso finito administrado por um Runtime especializado.

Nenhum componente deve montar prompts diretamente.

Nenhum Provider deve conhecer limites globais.

Toda decisão sobre utilização da janela de contexto deve passar pelo Context Runtime e pelo Budget Manager, permitindo que novas fontes de informação sejam adicionadas futuramente sem alterar a lógica central de construção do contexto.

Uma extensão que eu adicionaria

Há um componente que considero faltar nessa arquitetura, inspirado em runtimes modernos como Claude Code e Codex: um Context Planner entre o Budget Manager e os Providers.

Em vez de o Budget Manager simplesmente distribuir cotas fixas, o fluxo seria:

                 Request
                     │
                     ▼
             Context Planner
                     │
        Define a estratégia da interação
                     │
                     ▼
              Budget Manager
                     │
         Distribui budgets dinamicamente
                     │
     ┌───────────────┼────────────────┐
     ▼               ▼                ▼
 System         Memories         Conversation
 Provider        Providers          Provider
                     │
                     ▼
              Prompt Assembly
                     │
                     ▼
                    LLM

O Context Planner responde perguntas como:

Esta interação exige muita memória histórica ou apenas contexto recente?
É uma pergunta sobre o domínio do usuário ou sobre a conversa atual?
Vale a pena consultar RAG nesta requisição?
Preciso incluir um plano de execução?
Quanto orçamento cada provider deveria receber nesta interação específica?