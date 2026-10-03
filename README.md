# Airbnb Listing Performance: Text Mining & NLP Analysis

## Executive Summary

This project analyzes **3,985 Airbnb listings across 12 markets** to find what drives listing performance. Working in R with `tidytext` and `ggplot2`, I applied four text mining methods (word frequency, bigrams, sentiment analysis and TF-IDF) alongside a numerical analysis of price and review scores.

The most useful finding is a surprising one: **high rated and lower rated listings use nearly identical positive language (92.5% vs 92.7%)**, so tone doesn't predict ratings. For Airbnb, that means coaching hosts to sound more positive is likely wasted effort. The second clear finding is about price: entire homes have a median price of **$150 a night**, against **$75** for private rooms.

## Tools Used

- **Language:** R
- **Libraries:** `mongolite`, `tidytext`, `tidyverse`, `ggplot2`, `tm`, `sentimentr`, `topicmodels`, `wordcloud`, `RColorBrewer`
- **Database:** MongoDB Atlas (`sample_airbnb.listingsAndReviews`)
- **Visualization:** ggplot2 (R) + Tableau dashboard
- **Techniques:** Tokenization (splitting text into words), stop word removal (dropping filler like "the"), bigram extraction, Bing sentiment lexicon, TF-IDF weighting

## Dataset

| Metric | Value |
|---|---|
| Total listings analyzed | 3,985 |
| Markets covered | 12 |
| Top bigram | "walking distance" (1,211 occurrences) |
| Overall sentiment | 92.6% positive |

## Four Analytical Frameworks

### 1. Word Frequency Analysis
I split descriptions into words with `unnest_tokens()` and removed stop words with `anti_join()`. Top words: **apartment (7,816), bedroom (4,102), kitchen (4,012), bed (3,880), beach (3,183)**. Functional and spatial words dominate.

![Top Bigrams](images/04_top_bigrams.png)

### 2. Bigram Analysis
A bigram is a two word phrase. I pulled them out with `unnest_tokens()`, using `token = "ngrams"` and `n = 2`. The top 15 phrases fall into three predictable groups:
- **Proximity:** walking distance (1,211), minutes walk (687), metro station (588)
- **Bedroom:** double bed (688), size bed, queen size
- **Amenities:** air conditioning (603), free wifi (420), equipped kitchen

### 3. Sentiment Analysis (Bing Lexicon)
The Bing lexicon is a word list tagging words as positive or negative. I joined words to it with `get_sentiments("bing")`. Overall: **42,353 positive words vs 3,392 negative** (92.6% positive). The comparison that matters: high rated listings are 92.5% positive and lower rated ones are 92.7% positive. That's a difference of 0.2 percentage points.

![Sentiment Balance by Rating Group](images/07_sentiment_by_rating.png)

### 4. TF-IDF by Room Type
TF-IDF scores a word higher when it's common in one group of text but rare in the others. I used `bind_tf_idf()` to find the words that set each room type apart:
- **Entire home:** ocean, condo, unit
- **Private room:** ensuite, cozy, spare
- **Shared room:** capsule, pod, hostelworld

A description whose wording doesn't match its room type could set the wrong expectations for guests.

## Key Findings

### 1. Entire homes lead on both price *and* satisfaction
Entire homes: median **$150/night**, review score **93.5**. Private rooms: $75, 92.4. Shared rooms: 90.5. In this segment, higher prices don't lower satisfaction.

![Price Distribution by Room Type](images/01_price_by_room_type.png)
![Review Score by Room Type](images/02_review_score_by_room_type.png)

### 2. A premium price doesn't guarantee a premium experience
Hong Kong averages **$529/night** but scores only **91.2**. The Big Island scores **96.2** at just **$145/night**. A high price isn't a sign of high quality.

![Price by Market](images/03_price_by_market.png)

### 3. Tone doesn't predict ratings
The 0.2 percentage point gap in positive language between high and low performers is the most important finding in the project. Coaching hosts to write more positively is unlikely to raise their scores.

![Top Words by Rating Group](images/06_top_words_by_rating.png)

## Tableau Dashboard

Four KPI cards (total listings, average review, positive language %, top bigram) plus four panels (price vs review by market, review by room type, top bigrams, sentiment by rating group).

![Tableau Dashboard](images/05_tableau_dashboard.png)

## Recommendations

1. **Guide hosts on content, not tone.** Replace positivity coaching with content templates that include experiential details (what the neighborhood feels like, sensory details, how close the place is to specific landmarks).
2. **Flag listings whose wording doesn't fit the room type.** An entire home described in shared room vocabulary (or vice versa) could set up expectations the stay won't meet. TF-IDF flagging can catch these automatically.
3. **Start with Hong Kong.** It's the most expensive market ($529 a night) but scores only 91.2, so quality work there should pay off most.
4. **Build separate pricing tools for each room type.** The $150 vs $75 median gap between entire homes and private rooms is big enough to justify separate pricing products.
