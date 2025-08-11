import datetime
import os
import re

import arxiv

import config


def sanitize_filename(name):
    """
    macOS 및 다른 OS에서 파일명으로 사용할 수 없는 문자를 제거
    '_'로 변경
    """
    sanitized_name = re.sub(r'[\\/*?:"<>|]', "_", name)
    return sanitized_name


def collect_new_papers():
    """
    Arxiv에서 지정된 기간 동안의 새로운 AI관련 논문을 수집
    """
    days_to_search = config.DAYS_TO_SEARCH
    max_results = config.MAX_RESULTS
    ai_categories = config.AI_CATEGORIES

    print(f"collecting new papers during {days_to_search}day(s)")

    # ai_categories = ["cs.AI", "cs.LG", "cs.CV", "cs.CL", "cs.NE", "stat.ML"]
    query = " OR ".join(f"cat:{cat}" for cat in ai_categories)

    today_7am_kst = datetime.datetime.now().replace(
        hour=7, minute=0, second=0, microsecond=0
    )
    start_day_kst = today_7am_kst - datetime.timedelta(days=days_to_search)
    end_time_utc = today_7am_kst - datetime.timedelta(hours=9)
    start_time_utc = start_day_kst - datetime.timedelta(hours=9)

    client = arxiv.Client()
    search = arxiv.Search(
        query=query, max_results=max_results, sort_by=arxiv.SortCriterion.SubmittedDate
    )
    results = client.results(search)

    pdf_dir = "./pdfs"
    if not os.path.exists(pdf_dir):
        os.makedirs(pdf_dir)

    new_papers = []
    try:
        for result in results:
            published_time_utc = result.published.replace(tzinfo=None)
            if start_time_utc <= published_time_utc < end_time_utc:
                paper_info = {
                    "entry_id": result.entry_id,
                    "short_id": result.get_short_id(),
                    "title": result.title,
                    "authors": [author.name for author in result.authors],
                    "subjects": result.categories,
                    "abstract": result.summary.replace("\n", " "),
                    "pdf_url": result.pdf_url,
                    "published_time_utc": result.published.isoformat(),
                }
                new_papers.append(paper_info)

                try:
                    if result.categories:
                        primary_subject = result.categories[0]
                    else:
                        primary_subject = "Uncategorized"
                    subject_dir = os.path.join("pdfs", primary_subject)
                    sanitized_title = sanitize_filename(result.title)
                    pdf_filename = f"{sanitized_title}.pdf"
                    os.makedirs(subject_dir, exist_ok=True)

                    result.download_pdf(dirpath=subject_dir, filename=pdf_filename)
                    print(f"successed to download pdf: {subject_dir}/{pdf_filename}")

                except Exception as e:
                    print(f"failed to download pdf: {result.title[:30]}... - {e}")

    except arxiv.UnexpectedEmptyPageError:
        print("searching end.")
        pass

    print("-" * 50)
    print(f"found {len(new_papers)} paper(s)")
    return new_papers
