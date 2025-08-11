import json
import os
import time

import google.generativeai as genai


def process_papers_with_gemini(papers_to_process):
    if not papers_to_process:
        print("!!! nothing to translate.")
        return []

    print(f"translating {len(papers_to_process)} papers'('s) abstract")

    try:
        GOOGLE_API_KEY = os.environ.get("GOOGLE_API_KEY")
        genai.configure(api_key=GOOGLE_API_KEY)
        # model = genai.GenerativeModel("gemini-1.5-pro-latest")
        model = genai.GenerativeModel("gemini-1.5-flash-latest")
    except Exception as e:
        print(f"error: {e}")
        return papers_to_process

    processed_papers = []
    for paper in papers_to_process:
        try:
            prompt = f"""
            You are the expert of following paper's knowledge.
            Please translate the following English abstract into Korean.
            Provide only the translated Korean text.
            Except if the noun or verb is originally English.

            English Abstract:
            ---
            {paper['abstract']}
            ---
            """
            response = model.generate_content(prompt)
            paper["abstract_ko"] = response.text.strip()
        except Exception as e:
            paper["abstract_ko"] = "failed to translate"
            print(f"failed to translate: {paper['title'][:30]}... - {e}")

        processed_papers.append(paper)
        time.sleep(1)

    print("translating done")
    return processed_papers


def save_papers_to_json(papers_data, filename="papers.json"):
    print(f"saving processed paper data to '{filename}' file")
    with open(filename, "w", encoding="utf-8") as f:
        json.dump(papers_data, f, ensure_ascii=False, indent=4)
    print(f"save done")
