export const normalizeKanbanCardSubject = subject =>
  String(subject || '')
    .trim()
    .replace(/\s+/g, ' ')
    .toLowerCase();
