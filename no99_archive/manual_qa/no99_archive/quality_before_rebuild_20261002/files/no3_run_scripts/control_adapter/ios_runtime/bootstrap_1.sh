if [ "${QA_CURRENT_SCENE_ID:-}" = R14 ]; then
  run_and_validate_qa_first_launch || exit 1
else
  run_and_validate_qa_bootstrap || exit 1
fi
