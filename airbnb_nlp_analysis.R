# ============================================================
# AIRBNB LISTING PERFORMANCE: TEXT MINING & NLP ANALYSIS
# Author: Rashad Mohammed
# Course: Business Analysis with Unstructured Data (DAT-7475)
# Hult International Business School, Spring 2026
# ============================================================
# This script analyzes 3,985 Airbnb listings across 12 markets
# using four text mining frameworks (word frequency, bigrams,
# sentiment, TF-IDF) plus numerical analysis of price and
# review scores.
# ============================================================


# ============================================================
# SECTION 1: SETUP — Install & Load Packages
# ============================================================

# Uncomment the lines below if running for the first time
# install.packages("mongolite")
# install.packages(c("tidytext", "tidyverse", "wordcloud", "RColorBrewer",
#                    "topicmodels", "tm", "sentimentr", "ggplot2",
#                    "plotly", "reshape2"))

library(mongolite)
library(tidytext)
library(tidyverse)
library(wordcloud)
library(RColorBrewer)
library(topicmodels)
library(tm)
library(sentimentr)
library(ggplot2)
library(plotly)
library(reshape2)


# ============================================================
# SECTION 2: CONNECT TO MONGODB & LOAD DATA
# ============================================================
# Credentials are loaded from environment variables — NEVER
# hardcode them. Create a .env file (see .env.example) or set
# these variables in your R session before running this script.
#
# Required env vars:
#   MONGO_USER, MONGO_PASS, MONGO_HOST
# ============================================================

mongo_user <- Sys.getenv("MONGO_USER")
mongo_pass <- Sys.getenv("MONGO_PASS")
mongo_host <- Sys.getenv("MONGO_HOST")

if (mongo_user == "" || mongo_pass == "" || mongo_host == "") {
  stop("Missing MongoDB credentials. Set MONGO_USER, MONGO_PASS, MONGO_HOST in your environment.")
}

url <- sprintf(
  "mongodb+srv://%s:%s@%s/?appName=Cluster0",
  mongo_user, mongo_pass, mongo_host
)

airbnb <- mongo(
  collection = "listingsAndReviews",
  db         = "sample_airbnb",
  url        = url
)

# Verify connection
airbnb$count()

# Preview first 5 records
head_data <- airbnb$find(limit = 5)
print(head_data)

# Pull full dataset
df <- airbnb$find()

# Basic checks
nrow(df)
names(df)
head(df$description, 3)


# ============================================================
# SECTION 3: NUMERICAL ANALYSIS
# Goal: Understand how price and review scores vary
# by room type and market (location)
# ============================================================

df_clean <- df %>%
  mutate(
    price_num     = as.numeric(gsub("[^0-9.]", "", as.character(price))),
    review_score  = as.numeric(review_scores$review_scores_rating),
    num_reviews   = as.numeric(number_of_reviews),
    room_type     = as.factor(room_type),
    property_type = as.factor(property_type),
    market        = address$market,
    suburb        = address$suburb
  ) %>%
  filter(
    !is.na(price_num),
    !is.na(review_score),
    price_num > 0,
    price_num < 1000,    # remove extreme outliers
    review_score > 0
  ) %>%
  mutate(doc_id = row_number())

nrow(df_clean)
summary(df_clean[, c("price_num", "review_score", "num_reviews")])


# --- VISUAL 1: Price Distribution by Room Type ---
# Business meaning: Entire homes command higher prices —
# this sets the pricing context for the whole story

plot1 <- ggplot(df_clean, aes(x = room_type, y = price_num, fill = room_type)) +
  geom_boxplot(outlier.shape = NA, alpha = 0.8) +
  coord_cartesian(ylim = c(0, 500)) +
  scale_fill_brewer(palette = "Set2") +
  labs(
    title    = "Price Distribution by Room Type",
    subtitle = "Entire homes command significantly higher prices than private or shared rooms",
    x        = "Room Type",
    y        = "Price (USD)"
  ) +
  theme_minimal(base_size = 13) +
  theme(legend.position = "none")

print(plot1)


# --- VISUAL 2: Average Review Score by Room Type ---
# Business meaning: Does a higher price tier also mean
# higher guest satisfaction?

review_by_room <- df_clean %>%
  group_by(room_type) %>%
  summarise(
    avg_score = mean(review_score, na.rm = TRUE),
    count     = n()
  ) %>%
  arrange(desc(avg_score))

print(review_by_room)

plot2 <- ggplot(review_by_room,
                aes(x = reorder(room_type, avg_score), y = avg_score, fill = room_type)) +
  geom_col(alpha = 0.85, width = 0.6) +
  geom_text(aes(label = round(avg_score, 1)), hjust = -0.2, size = 4) +
  coord_flip(ylim = c(80, 100)) +
  scale_fill_brewer(palette = "Set2") +
  labs(
    title    = "Average Review Score by Room Type",
    subtitle = "Guest satisfaction is consistently high but varies by listing type",
    x        = "Room Type",
    y        = "Average Review Score (out of 100)"
  ) +
  theme_minimal(base_size = 13) +
  theme(legend.position = "none")

print(plot2)


# --- VISUAL 3: Market Comparison — Price + Review Score ---
# Business meaning: Location shapes both price and perception.
# Color encodes review score to show if premium markets also
# earn stronger guest ratings

market_summary <- df_clean %>%
  filter(!is.na(market), market != "") %>%
  group_by(market) %>%
  summarise(
    avg_price     = mean(price_num, na.rm = TRUE),
    avg_review    = mean(review_score, na.rm = TRUE),
    listing_count = n()
  ) %>%
  filter(listing_count >= 10) %>%
  arrange(desc(avg_price))

print(market_summary)

plot3 <- ggplot(market_summary,
                aes(x = reorder(market, avg_price), y = avg_price, fill = avg_review)) +
  geom_col(alpha = 0.85) +
  coord_flip() +
  scale_fill_gradient(low = "#f7c59f", high = "#d62828", name = "Avg Review\nScore") +
  labs(
    title    = "Average Listing Price by Market",
    subtitle = "Color shows average review score — do higher priced markets also score better?",
    x        = "Market",
    y        = "Average Price (USD)"
  ) +
  theme_minimal(base_size = 12)

print(plot3)


# ============================================================
# SECTION 4: TEXT PREPARATION
# Goal: Clean listing descriptions for all text frameworks
# ============================================================

text_df <- df %>%
  select(name, summary, description, room_type, property_type, price) %>%
  mutate(
    doc_id    = row_number(),
    full_text = paste(name, summary, description, sep = " ")
  ) %>%
  filter(!is.na(full_text), full_text != "") %>%
  mutate(full_text = str_squish(full_text))

# Tokenize and clean — shared base for all text mining frameworks
tokens <- text_df %>%
  unnest_tokens(word, full_text) %>%
  anti_join(stop_words, by = "word") %>%
  filter(
    !str_detect(word, "^\\d+$"),
    str_detect(word, "[a-z]"),
    nchar(word) > 2
  )

head(tokens, 10)


# ============================================================
# SECTION 5: FRAMEWORK 1 — WORD FREQUENCY
# Business meaning: What do hosts emphasize most in their
# descriptions? Reveals core positioning language.
# ============================================================

word_freq <- tokens %>%
  count(word, sort = TRUE)

head(word_freq, 20)

word_freq %>%
  slice_max(n, n = 15) %>%
  ggplot(aes(x = reorder(word, n), y = n)) +
  geom_col(fill = "#1565C0", alpha = 0.85) +
  coord_flip() +
  labs(
    title    = "Top 15 Most Frequent Words in Airbnb Listings",
    subtitle = "Hosts consistently emphasize location, space, and comfort",
    x        = "Word",
    y        = "Frequency"
  ) +
  theme_minimal(base_size = 13)


# ============================================================
# SECTION 6: FRAMEWORK 2 — BIGRAM ANALYSIS
# Business meaning: Phrase pairs reveal the specific selling
# language hosts use — more meaningful than single words alone
# ============================================================

bigrams_separated <- text_df %>%
  unnest_tokens(bigram, full_text, token = "ngrams", n = 2) %>%
  filter(!is.na(bigram)) %>%
  separate(bigram, into = c("word1", "word2"), sep = " ") %>%
  filter(
    !word1 %in% stop_words$word,
    !word2 %in% stop_words$word,
    !str_detect(word1, "^\\d+$"),
    !str_detect(word2, "^\\d+$"),
    nchar(word1) > 2,
    nchar(word2) > 2
  )

bigram_counts <- bigrams_separated %>%
  unite(bigram, word1, word2, sep = " ") %>%
  count(bigram, sort = TRUE)

head(bigram_counts, 20)

plot4 <- bigram_counts %>%
  slice_max(n, n = 15) %>%
  ggplot(aes(x = reorder(bigram, n), y = n)) +
  geom_col(fill = "#2196F3", alpha = 0.85) +
  coord_flip() +
  labs(
    title    = "Top 15 Bigrams in Airbnb Listing Descriptions",
    subtitle = "Repeated phrase pairs reveal the core selling language hosts use",
    x        = "Bigram",
    y        = "Frequency"
  ) +
  theme_minimal(base_size = 13)

print(plot4)


# ============================================================
# SECTION 7: FRAMEWORK 3 — SENTIMENT ANALYSIS (Bing lexicon)
# Business meaning: Are listing descriptions overwhelmingly
# positive? Does positive language align with higher ratings?
# ============================================================

bing_sentiment <- tokens %>%
  inner_join(get_sentiments("bing"), by = "word") %>%
  count(sentiment, sort = TRUE)

print(bing_sentiment)

# Visual: Top positive and negative words overall
tokens %>%
  inner_join(get_sentiments("bing"), by = "word") %>%
  count(word, sentiment, sort = TRUE) %>%
  group_by(sentiment) %>%
  slice_max(n, n = 10) %>%
  ungroup() %>%
  ggplot(aes(x = reorder(word, n), y = n, fill = sentiment)) +
  geom_col(show.legend = FALSE, alpha = 0.85) +
  facet_wrap(~sentiment, scales = "free_y") +
  coord_flip() +
  scale_fill_manual(values = c("positive" = "#388e3c", "negative" = "#d32f2f")) +
  labs(
    title    = "Top Positive and Negative Words in Listings",
    subtitle = "Positive words dominate — hosts use aspirational and comfort-driven language",
    x        = "Word",
    y        = "Count"
  ) +
  theme_minimal(base_size = 13)


# ============================================================
# SECTION 8: CONNECT TEXT TO BUSINESS OUTCOMES
# Goal: Do high-rated listings use different language?
# This links NLP directly to business performance.
# ============================================================

# Join text with review scores using doc_id
text_scored <- text_df %>%
  left_join(
    df_clean %>% select(doc_id, review_score, price_num, room_type),
    by = "doc_id"
  ) %>%
  filter(!is.na(review_score)) %>%
  mutate(
    rating_group = case_when(
      review_score >= 90 ~ "High Rated (90+)",
      review_score < 90  ~ "Lower Rated (<90)"
    )
  )

table(text_scored$rating_group)

# Tokenize scored text
tokens_scored <- text_scored %>%
  unnest_tokens(word, full_text) %>%
  anti_join(stop_words, by = "word") %>%
  filter(
    !str_detect(word, "^\\d+$"),
    str_detect(word, "[a-z]"),
    nchar(word) > 2
  )


# --- VISUAL: Top Words — High Rated vs Lower Rated ---
# Business meaning: Vocabulary differences show what
# high-performing hosts actually emphasize

top_words_by_rating <- tokens_scored %>%
  count(rating_group, word, sort = TRUE) %>%
  group_by(rating_group) %>%
  slice_max(n, n = 15) %>%
  ungroup()

plot5 <- top_words_by_rating %>%
  ggplot(aes(x = reorder(word, n), y = n, fill = rating_group)) +
  geom_col(show.legend = FALSE, alpha = 0.85) +
  facet_wrap(~rating_group, scales = "free") +
  coord_flip() +
  scale_fill_manual(values = c("High Rated (90+)"  = "#2e7d32",
                               "Lower Rated (<90)" = "#c62828")) +
  labs(
    title    = "Top Words: High Rated vs Lower Rated Listings",
    subtitle = "Vocabulary differences reveal what high-performing hosts emphasize",
    x        = "Word",
    y        = "Frequency"
  ) +
  theme_minimal(base_size = 12)

print(plot5)


# --- VISUAL: Sentiment Balance by Rating Group ---
# Business meaning: Does more positive language appear
# in higher rated listings?

sentiment_by_rating <- tokens_scored %>%
  inner_join(get_sentiments("bing"), by = "word") %>%
  count(rating_group, sentiment) %>%
  group_by(rating_group) %>%
  mutate(pct = n / sum(n) * 100) %>%
  ungroup()

print(sentiment_by_rating)

plot6 <- sentiment_by_rating %>%
  ggplot(aes(x = rating_group, y = pct, fill = sentiment)) +
  geom_col(position = "dodge", alpha = 0.85, width = 0.6) +
  scale_fill_manual(values = c("positive" = "#388e3c", "negative" = "#d32f2f")) +
  labs(
    title    = "Sentiment Balance: High Rated vs Lower Rated Listings",
    subtitle = "Difference is only 0.2 percentage points — tone does not predict performance",
    x        = "Rating Group",
    y        = "Percentage of Sentiment Words (%)",
    fill     = "Sentiment"
  ) +
  theme_minimal(base_size = 13)

print(plot6)


# ============================================================
# SECTION 9: FRAMEWORK 4 — TF-IDF BY ROOM TYPE
# Business meaning: What words uniquely define each
# listing type beyond what all listings share?
# ============================================================

tfidf_words <- tokens %>%
  count(room_type, word, sort = TRUE) %>%
  bind_tf_idf(word, room_type, n) %>%
  arrange(desc(tf_idf))

head(tfidf_words, 20)

tfidf_words %>%
  group_by(room_type) %>%
  slice_max(tf_idf, n = 10) %>%
  ungroup() %>%
  ggplot(aes(x = reorder(word, tf_idf), y = tf_idf, fill = room_type)) +
  geom_col(show.legend = FALSE, alpha = 0.85) +
  facet_wrap(~room_type, scales = "free") +
  coord_flip() +
  labs(
    title    = "Top TF-IDF Words by Room Type",
    subtitle = "Each room type has distinct descriptive language that sets it apart",
    x        = "Word",
    y        = "TF-IDF Score"
  ) +
  theme_minimal(base_size = 12)


# ============================================================
# END OF ANALYSIS
# ============================================================
