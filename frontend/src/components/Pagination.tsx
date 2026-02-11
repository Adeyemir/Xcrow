interface PaginationProps {
  page: number;
  totalPages: number;
  onPageChange: (page: number) => void;
}

export function Pagination({ page, totalPages, onPageChange }: PaginationProps) {
  if (totalPages <= 1) return null;

  return (
    <div
      className="flex items-center justify-between px-4 py-3"
      style={{ borderTop: "1px solid var(--border-secondary)" }}
    >
      <div className="text-xs tabular-nums" style={{ color: "var(--text-tertiary)" }}>
        Page {page} of {totalPages}
      </div>
      <div className="flex gap-2">
        <button
          onClick={() => onPageChange(page - 1)}
          disabled={page <= 1}
          className="btn-ghost px-3 py-1 text-xs disabled:opacity-30"
        >
          ← Prev
        </button>
        <button
          onClick={() => onPageChange(page + 1)}
          disabled={page >= totalPages}
          className="btn-ghost px-3 py-1 text-xs disabled:opacity-30"
        >
          Next →
        </button>
      </div>
    </div>
  );
}
