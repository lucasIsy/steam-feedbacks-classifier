![fluxograma](assets/Fluxograma.svg)

# Introdução
Converter milhares de feedbacks em informações estratégicas é um gargalo para qualquer área que dependa de atualizações constantes. A complexidade de lidar com esses textos é a principal razão dos desenvolvedores de jogos não conseguirem utilizar a Steam, a maior plataforma de jogos do mundo, como fonte de dados.

A arquitetura de dados criada resolveu esse problema com base em 3 pilares(filtragem, fragmentação e classificação) através da união do tradicional fluxo ELT com IA, embeddings e RAG, automatizando a entrega de dados estratégicos para jogos em desenvolvimento.

> *O projeto também aborda estratégias para reduzir custos com BigQuery, Gemini 3.1 e criação de inferência em lote global.* 

## Por que tratar as reviews da Steam são um pesadelo?
A plataforma permite um estilo livre na criação de reviews, isso significa que o usuário pode escrever o que quiser, da forma que achar melhor e enviar. Por causa dessa liberdade, era esperado problemas comuns de linguagem informal(erros de gramática, gírias e etc.), mas no caso da Steam é necessário estar preparado para lidar com conteúdos extremamente problemáticos, que vão desde emojis, conteúdo sexual, discurso de ódio até apologia a grupos terroristas.

> A complexidade de ignorar esses problemas e extrair apenas as reviews úteis é o que força os desenvolvedores a encontrarem outros meios para receber feedbacks, deixando a Steam de lado.

|Ruídos|Complexidade|Soluções|Lado negativo|
|---|---|---|---|
|EMOJIS|Fácil|SQL + REGEX|Custo Computacional|
|Sentimentos genéricos(bom, ruim...)|Fácil|SQL + REGEX|Custo Computacional|
|ASCII ART(simples e complexa)|Média|SQL + REGEX|Custo Computacional|
|Assuntos aleatórios|ALTA|PROMPT + LLM|Inferência, falsos positivos, tokens, prompt e modelo|
|Reclamações/Problemas sem causador|ALTA|PROMPT + LLM|Inferência, falsos positivos, tokens, prompt e modelo|
|Copy Pastas|MÁXIMA|PROMPT + LLM|Inferência, falsos positivos, tokens, prompt e modelo|
|Spam de caracteres espaçados|MÁXIMA|INDEFINIDO|Alto custo computacional sem garantias de sucesso|
|Conteúdos nocivos|MÁXIMA|INDEFINIDO|Risco aos termos de serviços da IA|

# Engenharia de dados + IA: os 3 pilares

<br>
<p align="center">
  <img src="assets/3-pilares.svg" alt="Exemplos" width="100%">
</p>

## Filtragem(maior redutor de custos com IA)
O objetivo é garantir que **apenas dados úteis** avancem para as próximas etapas, que envolvem custos com IA(Gemini 3.1) e embeddings, por isso foi dividida em duas partes: 
* **Corte + Regex**: remove conteúdos baseados no tamanho da review(caracteres e espaços) antes e depois do regex, garantindo que apenas letras e pontuação permitida avancem - não gastar tokens processando imagens ascii ou emojis.
* **Classificação booleana**: determina se a review possui algum conteúdo relevante para o desenvolvimento do jogo com base em critérios estipulados e output definido(prompt).

> Quanto mais eficiente for as técnicas de filtragem, menor será o gasto com tokens e embeddings, mas do contrário, as etapas posteriores vão gastar mais e a qualidade nos dados estará comprometida.

<p align="center">
  <img src="assets/Exemplo-filtro-2.svg" alt="Exemplos" width="100%">
</p>

*⚠ Está sendo estudado o uso de embeddings para remover conteúdos aleatórios/nocivos.*

## Fragmentação
**Objetivo Final:** Permitir que o desenvolvedor possa selecionar um topico e descobrir rapidamente quais problemas são recorrentes

**Problema:** 
1. As reviews podem falar sobre um ou mais assuntos, não necessariamente sobre o mesmo tema.
2. Problemas recorrentes nascem de fatos recorrentes, então vão existir reviews sobre o mesmo assunto, mas escritas de formas diferentes.

**Solução:**
1. Isolar cada fato em um fragmento de review independente com sua classe e Topicos - colunas para facilitar o agrupamento, filtragem SQL e metadados de VectorDB.
2. Fazer com que relatos iguais, mas escritos de formas diferentes tenham resumos parecidos - **O mesmo fato gera resumos semanticamente próximos**

**Observação**
O resumo estratégico é o coração da etapa de classificação, pois ele é a base para a geração dos embeddings e herança por similaridade semântica. Porém, o desempenho da classificação pode mudar drasticamente se a criação desses resumos não forem bem definidas no prompt, além do tamanho dos vetores e modelo utilizado.

<br>

<p align="center">
  <img src="assets/Exemplo-fragmentacao-1.svg" alt="Exemplos" width="80%">
</p>

## Classificação
Com a fragmentação, problemas recorrentes geram resumos semelhantes(o mesmo causador), o que permite separar o que é conhecido do desconhecido através da distância semântica. Cada fragmento deve filtrar o vectorDB e trazer apenas os candidatos que vão de acordo com sua classe e topico,evitando comparar um bug de performance com uma insatisfação sobre a falta de transparência com o jogo. 

> Partindo dessa premissa, fragmentos próximos aos que existem no vectorDB são marcados como conhecidos e vão direto pra gold, mas os desconhecidos vão para a fila de RAG.

<br>

<p align="center">
  <img src="assets/Exemplo-classificacao-1.svg" alt="Exemplos" width="100%">
</p>

# Guia do Projeto e Observações

``` text
Projeto/
├── Explicação do Pipeline/
│   ├── Extação-Load/ # Problema da API Steam, Pré-processamento, Parquet
│   ├── Transformação/
│   │   ├── Filtragem/ # Corte, REGEX, verificação de continuidade, pré-inferência e inferência em lote.
│	│   ├── Router/ # Determina se o pipeline continua ou não e direciona os dados para fragmentação, silver ou DLQ.
│   │   ├── Fragmentação/ # Pré-inferência, inferência em lote e Array Struct dos fragmentos para classificação.
│	│   ├── Router/ # Determina se o pipeline continua ou não e direciona os dados para classificação ou DLQ.
│   │   ├── Classificação/ # Unnest dos structs, BigQuery ML + modelos remotos(Gemini embedding), direcionamento dos dados para Gold e VectorDB.
│   ├── Otimizações-Idempotência/ # Aborda reprocessamento, retrys, gastos com IA, ingestão incremental, partição, clustering e vector index.
└── Pipeline/
```

A arquitetura foi projetada para ser eficiente com os recursos de IA e Embeddings, além de ser imdepotente. Os recursos de inferência são utilizados apenas se houver reviews marcadas como relevantes. 

O projeto foi criado inteiramente no Google Cloud Platafform usando os seguintes recursos:
- BigQuery
	- Otimização das tabelas para modelo ON-DEMAND
	- Procedures
	- Filtragem
	- Modelos Remotos
	- Pré-inferência(coluna request)
	- VectorDB
- Cloud Run/Function
	- Extração inteligente dos dados da Steam
	- Criação de Inferência flex/batch
- Agent Platafform
	- Gemini 3.1(filtragem / fragmentação)
	- Gemini Embeddings(Classificação)
- Cloud Workflow
	- orquestração inteligente das procedures e recursos de IA

