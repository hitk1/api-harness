defmodule ApiHarness.Context.Compaction.Prompt do
  @moduledoc "Builds the LLM prompt for generating a rolling summary of conversation history."

  @doc """
  Builds a compaction prompt from a list of messages and an optional existing summary.
  The resulting summary should follow the 9-section structure.
  """
  @spec build([map()], String.t() | nil) :: String.t()
  def build(messages, existing_summary \\ nil) do
    max_tokens =
      Application.get_env(:api_harness, :context_budget, [])[:rolling_summary_max_tokens] ||
        8_000

    conversation_text =
      messages
      |> Enum.map(fn msg -> "[#{String.upcase(msg.role)}]: #{msg.content}" end)
      |> Enum.join("\n\n")

    previous_summary_section =
      if existing_summary do
        """

        ## Resumo Anterior
        #{existing_summary}

        ## Novas Mensagens Desde o Último Resumo
        """
      else
        "\n## Conversa Completa\n"
      end

    """
    Você é um assistente especializado em criar resumos estruturados de conversas.
    Analise a conversa abaixo e produza um resumo estruturado seguindo EXATAMENTE as 9 seções abaixo.
    O resumo deve ter no máximo #{max_tokens} tokens. Seja conciso mas completo.
    Preserve as mensagens do usuário de forma literal (não parafraseie).
    #{previous_summary_section}
    #{conversation_text}

    ## Formato do Resumo (OBRIGATÓRIO)

    Produza o resumo nas seguintes seções:

    ### 1. Pedido e Intenção Primária
    [Capture todos os pedidos e intenções explícitas do usuário de forma literal]

    ### 2. Conceitos Técnicos-Chave
    [Liste todos os conceitos técnicos]

    ### 3. Arquivos e Trechos de Código
    [Enumere arquivos e trechos específicos examinados, modificados ou criados]

    ### 4. Erros e Correções
    [Liste todos os erros que apareceram e como foram corrigidos]

    ### 5. Resolução de Problemas
    [Documente problemas resolvidos e investigações em andamento]

    ### 6. Mensagens do Usuário
    [Liste TODAS as mensagens do usuário de forma literal - são críticas]

    ### 7. Tarefas Pendentes
    [Liste tarefas pendentes que foram explicitamente solicitadas]

    ### 8. Trabalho Atual
    [Descreva em detalhe o que estava sendo feito imediatamente antes desta solicitação]

    ### 9. Próximo Passo (Opcional)
    [Liste o próximo passo planejado, se conhecido]
    """
  end
end
