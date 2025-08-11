# Arxiv newest paper crawler

---

## How to use

I recommend you to make new python env for managing this crawler.

Before start, you should export your `GOOGLE_API_KEY` for trasnlating the abstract of papers. You can skip if you don't need the translated abstract.

```bash
export GOOGLE_API_KEY="YOUR_API_KEY"
pip install .
python main.py
```

You can choose how the workflow working via

```bash
python main.py all
python main.py process
python main.py serve
```

- 'all': runs the whole workflow of crawler.
- 'process': runs downloading the papers, translating and making metadata(favorites.json, papers.json).
- 'serve': runs web app via flask.

## Adjust the config file

In `config.py` you can adjust how long you want to crawl and etc.

Please check the `config.py` file.

---

## TODO

- Make deleting locally downloaded papers option.
- Seperate workflow with more options.
