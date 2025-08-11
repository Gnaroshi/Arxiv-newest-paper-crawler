# import datetime
# import os
#
# from arxiv_collector import collect_new_papers
# from translator import process_papers_with_gemini, save_papers_to_json
# from webapp import run_web_app
#
#
# def main():
#     data_file = "papers.json"
#     should_run_workflow = True
#
#     if os.path.exists(data_file):
#         mod_time_stamp = os.path.getmtime(data_file)
#         mod_datetime = datetime.datetime.fromtimestamp(mod_time_stamp)
#
#         today_7am = datetime.datetime.now().replace(
#             hour=7, minute=0, second=0, microsecond=0
#         )
#
#         if mod_datetime > today_7am:
#             print(f"today's paper data is already exist.")
#             print("skipping collecting and translating, starting webapp.")
#             should_run_workflow = False
#
#     if should_run_workflow:
#         print("Starting workflow - arxiv new paper crawling")
#
#         new_papers = collect_new_papers()
#         processed_papers = process_papers_with_gemini(new_papers)
#         save_papers_to_json(processed_papers, data_file)
#
#     run_web_app()
#
#
# if __name__ == "__main__":
#     main()

import argparse
import datetime
import os

# Import functions from other modules
from arxiv_collector import collect_new_papers
from translator import process_papers_with_gemini, save_papers_to_json
from webapp import run_web_app


def run_processing_workflow():
    data_file = "papers.json"
    should_run_workflow = True

    if os.path.exists(data_file):
        mod_time_stamp = os.path.getmtime(data_file)
        mod_datetime = datetime.datetime.fromtimestamp(mod_time_stamp)
        today_7am = datetime.datetime.now().replace(
            hour=7, minute=0, second=0, microsecond=0
        )

        if mod_datetime > today_7am:
            print(f"Today's paper data ('{data_file}') already exists.")
            should_run_workflow = False

    if should_run_workflow:
        print("Starting the ArXiv Paper Processing Workflow")
        new_papers = collect_new_papers()

        processed_papers = process_papers_with_gemini(new_papers)

        save_papers_to_json(processed_papers, data_file)
    else:
        print("Skipping data processing.")


def main():
    parser = argparse.ArgumentParser(description="A workflow manager for ArXiv papers.")
    parser.add_argument(
        "action",
        nargs="?",
        default="all",
        choices=["process", "serve", "all"],
        help="The action to perform: 'process' (collect & translate), 'serve' the web app, or 'all' (default).",
    )
    args = parser.parse_args()

    if args.action in ["all", "process"]:
        run_processing_workflow()

    if args.action in ["all", "serve"]:
        run_web_app()


if __name__ == "__main__":
    main()
