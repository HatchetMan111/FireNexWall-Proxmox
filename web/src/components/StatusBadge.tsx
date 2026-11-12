import { statusLabels } from "../lib/format";
import type { ReleaseStatus } from "../lib/types";

export default function StatusBadge({ status }: { status: ReleaseStatus }) {
  return (
    <span className={`badge badge-${status}`}>{statusLabels[status]}</span>
  );
}
