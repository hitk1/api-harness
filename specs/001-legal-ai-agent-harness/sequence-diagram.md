# Diagrama de Sequência — Legal AI Agent Harness

```mermaid
sequenceDiagram
    autonumber

    actor Client
    participant Auth as Authenticate Plug
    participant MC as MessageController
    participant FB as FallbackController
    participant Accounts
    participant Chats
    participant Memory
    participant Runtime as Agent Runtime
    participant CB as ContextBuilder
    participant Executor
    participant Coord as Coordinator
    participant Tools as Tools Registry
    participant Sup as Pipeline Supervisor
    participant Worker as Pipeline Worker
    participant Extractor
    participant Planner
    participant Retriever
    participant Reconciler
    participant OpenAI as OpenAI API
    participant DB as PostgreSQL pgvector

    Note over Client,DB: FLUXO 1 - Autenticacao POST /api/login

    Client->>MC: POST /api/login email e password
    MC->>Accounts: get_user_by_email(email)
    Accounts->>DB: SELECT WHERE lower(email) = email
    DB-->>Accounts: User ou nil
    alt usuario encontrado
        MC->>Accounts: verify_password(user, password)
        Accounts-->>MC: ok ou error
    else usuario nao existe
        MC->>Accounts: no_user_verify()
        Note right of Accounts: bcrypt constante evita timing attack
    end
    MC->>Accounts: Token.generate(user)
    Note right of Accounts: JWT HS256 com sub e token_version sem exp
    MC-->>Client: 200 token e user ou 401

    Note over Client,DB: FLUXO 2 - Mensagem POST /api/chats/id/messages

    Client->>Auth: POST /api/chats/id/messages + Bearer JWT
    activate Auth
    Auth->>Accounts: Token.verify(jwt)
    Auth->>DB: SELECT user WHERE id = sub
    DB-->>Auth: User
    Auth->>Auth: verifica token_version para revogacao
    Auth->>MC: conn com current_user
    activate MC

    MC->>Chats: get_chat(current_user, chat_id)
    Chats->>DB: SELECT chats WHERE id AND user_id
    DB-->>MC: Chat ou nil

    alt chat nao encontrado ou de outro usuario
        MC->>FB: error not_found
        FB-->>Client: 404
    end

    MC->>Runtime: run(user, chat, content)
    activate Runtime
    Runtime->>Chats: add_message(chat, user, content)
    Chats->>DB: INSERT messages

    Runtime->>CB: build(user, chat, question)
    activate CB
    CB->>Memory: list_persistent_memories_by_category(user_id, domain)
    Memory->>DB: SELECT persistent_memories WHERE category = domain
    DB-->>Memory: memorias de dominio
    Memory-->>CB: domain memories
    CB->>Memory: get_session_memory(chat_id)
    Memory->>DB: SELECT session_memories WHERE chat_id
    DB-->>Memory: estado da sessao
    Memory-->>CB: session memory state
    CB->>Retriever: retrieve(user_id, question, k=5)
    activate Retriever
    Retriever->>OpenAI: POST /embeddings text-embedding-3-small
    OpenAI-->>Retriever: vetor 1536 dimensoes
    Retriever->>DB: SELECT memories ORDER BY embedding cosseno LIMIT 5
    DB-->>Retriever: PersistentMemory list
    Retriever-->>CB: memorias relevantes category user e task
    deactivate Retriever
    CB->>Chats: list_recent_messages(chat, 10)
    Chats->>DB: SELECT messages ORDER BY inserted_at DESC id DESC LIMIT 10
    DB-->>Chats: ultimas mensagens
    Chats-->>CB: mensagens recentes
    CB-->>Runtime: prompt com 6 camadas montadas
    deactivate CB
    Note right of CB: Camadas 1-4 no system message / Camada 5 historico / Camada 6 pergunta

    Runtime->>Planner: plan(messages)
    activate Planner
    Planner->>OpenAI: POST /chat/completions json_schema agent_plan
    alt OpenAI indisponivel
        OpenAI-->>Planner: erro HTTP
        Planner-->>Runtime: error llm_unavailable
        Runtime-->>MC: error llm_unavailable
        MC->>FB: error llm_unavailable
        FB-->>Client: 502 ai provider unavailable
    else OpenAI disponivel
        OpenAI-->>Planner: steps com type tool ou answer
        Planner-->>Runtime: ok steps
    end
    deactivate Planner

    Runtime->>Executor: execute(steps, messages)
    activate Executor

    opt existem tool steps no plano
        Executor->>Coord: run(parallel_steps)
        activate Coord
        par executando em paralelo via Task.async_stream
            Coord->>Tools: execute search_entities
        and
            Coord->>Tools: execute read_document
        end
        Tools-->>Coord: ok results
        Coord-->>Executor: ok results ou error tool_failed
        deactivate Coord
    end

    Executor->>OpenAI: POST /chat/completions answer step
    OpenAI-->>Executor: resposta juridica estruturada
    Executor-->>Runtime: ok answer
    deactivate Executor

    Runtime->>Chats: add_message(chat, assistant, answer)
    Chats->>DB: INSERT messages
    Runtime->>Memory: update_session_memory(chat_id, summary)
    Memory->>DB: UPSERT session_memories merge state
    Runtime-->>MC: ok assistant message
    deactivate Runtime
    MC-->>Client: 200 message id role content
    deactivate MC
    deactivate Auth

    Note over Sup,DB: FLUXO 3 - Pipeline de Memoria fire-and-forget apos HTTP 200

    MC->>Sup: dispatch_pipeline(user, chat, assistant_msg)
    Note right of MC: qualquer falha e descartada silenciosamente via rescue

    Sup->>Worker: DynamicSupervisor.start_child restart temporary
    activate Worker
    Note right of Worker: 3 tentativas com backoff linear

    Worker->>Extractor: extract(assistant_msg)
    activate Extractor
    Extractor->>OpenAI: POST /chat/completions json_schema knowledge_extraction
    OpenAI-->>Extractor: items com category kind content durable
    Extractor-->>Worker: ok candidates
    deactivate Extractor

    Worker->>Reconciler: reconcile(user_id, candidates)
    activate Reconciler

    loop para cada candidato extraido
        alt durable false
            Note right of Reconciler: action discard sem consulta ao DB
        else durable true
            Reconciler->>Retriever: retrieve(user_id, content, k=1, category)
            activate Retriever
            Retriever->>DB: cosine similarity query
            DB-->>Retriever: memoria mais proxima ou vazio
            Retriever-->>Reconciler: nearest memory
            deactivate Retriever
            alt sem memoria proxima
                Note right of Reconciler: action create
            else memoria existente encontrada
                Reconciler->>OpenAI: POST /chat/completions json_schema memory_reconciliation
                OpenAI-->>Reconciler: action create update merge ou discard
            end
        end
    end

    Reconciler-->>Worker: ok candidates anotados com action
    deactivate Reconciler

    Worker->>Memory: apply_reconciliation(user_id, candidates)
    loop para cada candidato anotado
        alt action create
            Memory->>DB: INSERT persistent_memories
        else action update ou merge
            Memory->>DB: UPDATE persistent_memories SET content
        end
        Memory->>DB: INSERT memory_context_updates audit trail
    end
    deactivate Worker
```

---

## Leitura por camadas

| # | Fluxo | Participantes-chave | Resultado |
|---|-------|---------------------|-----------|
| 1 | Autenticacao | Client, Accounts, Token | JWT HS256 com token_version |
| 2 | Mensagem (sincrono) | Auth Plug, Runtime, CB, Planner, Executor, OpenAI | HTTP 200 com resposta do assistente |
| 3 | Memoria (assincrono) | Worker, Extractor, Reconciler, pgvector | Conhecimento consolidado no DB |

## Propriedades do design

- **Resposta antes da memoria (SC-002):** o HTTP 200 e enviado ao cliente antes do `dispatch_pipeline` iniciar o Worker. Falhas no pipeline nunca afetam o usuario.
- **Planner obrigatorio (FR-010-A):** toda mensagem passa pelo Planner sem bypass. Falha do LLM retorna 502 (`llm_unavailable`), nao 422.
- **Revogacao de tokens sem blocklist:** `token_version` no JWT e comparado com o valor no DB a cada request. Incrementar o campo invalida todos os tokens anteriores.
- **Protecao contra timing attack:** `no_user_verify()` executa bcrypt mesmo quando o e-mail nao existe, garantindo tempo de resposta constante.
- **Fail-total no Coordinator:** se qualquer ferramenta paralela falha, `Task.async_stream` com `reduce_while` interrompe todas as demais imediatamente.
- **Worker efemero (restart: temporary):** o Supervisor nao reinicia Workers que falham. O pipeline tenta ate 3 vezes internamente com backoff linear e depois descarta com log.
