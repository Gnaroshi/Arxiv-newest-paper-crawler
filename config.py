# Settings for Arxiv Search
# ------------------------------------

# The number of days back to search for papers
# DAYS_TO_SEARCH = 5
DAYS_TO_SEARCH = 5

# The maximum number of papers to fetch
# MAX_RESULTS = 200
MAX_RESULTS = 10

# List of AI-related Arxiv categories to search.
AI_CATEGORIES = [
    "cs.AI",  # Artificial Intelligence
    "cs.LG",  # Machine Learning
    "cs.CV",  # Computer Vision and Pattern Recognition
    "cs.CL",  # Computation and Language
    "cs.NE",  # Neural and Evolutionary Computing
    "stat.ML",  # Statistics - Machine Learning
]

SUBJECT_MAP = {
    "cs.AI": "Artificial Intelligence",
    "cs.LG": "Machine Learning",
    "cs.CV": "Computer Vision and Pattern Recognition",
    "cs.CL": "Computation and Language",
    "cs.NE": "Neural and Evolutionary Computing",
    "stat.ML": "Statistics - Machine Learning",
}

# Settings for Gemini API
# ------------------------------------
# (recommend to use an environment variable for the API key)
# export GOOGLE_API_KEY="YOUR_API_KEY"

# Delay in seconds between each translation task to avoid hitting API rate limits.
TRANSLATION_DELAY = 1
