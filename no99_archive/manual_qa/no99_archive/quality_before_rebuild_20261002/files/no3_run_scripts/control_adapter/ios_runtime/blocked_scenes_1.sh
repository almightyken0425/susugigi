for qa_scene_id in "${QA_SCENE_IDS[@]}"; do
  case "$qa_scene_id" in
    R10|R11|R12)
      printf '%s\n' QA_STRUCTURED_BLOCKED_SCENE_REJECTED >&2
      exit 1
      ;;
  esac
done
