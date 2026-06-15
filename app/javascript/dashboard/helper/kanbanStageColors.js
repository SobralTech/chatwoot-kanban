export const DEFAULT_KANBAN_STAGE_COLOR = 'slate';

const STAGE_COLOR_CLASSES = {
  slate: 'bg-n-slate-9',
  blue: 'bg-n-blue-9',
  teal: 'bg-n-teal-9',
  green: 'bg-green-500',
  amber: 'bg-n-amber-9',
  orange: 'bg-orange-500',
  ruby: 'bg-n-ruby-9',
  rose: 'bg-rose-500',
  violet: 'bg-n-violet-9',
  iris: 'bg-n-iris-9',
};

const STAGE_BODY_COLOR_CLASSES = {
  slate: 'bg-n-slate-2',
  blue: 'bg-n-blue-2',
  teal: 'bg-n-teal-2',
  green: 'bg-green-50 dark:bg-green-950/30',
  amber: 'bg-n-amber-2',
  orange: 'bg-orange-50 dark:bg-orange-950/30',
  ruby: 'bg-n-ruby-2',
  rose: 'bg-rose-50 dark:bg-rose-950/30',
  violet: 'bg-n-violet-2',
  iris: 'bg-n-iris-2',
};

export const KANBAN_STAGE_COLOR_OPTIONS = [
  'slate',
  'blue',
  'teal',
  'green',
  'amber',
  'orange',
  'ruby',
  'rose',
  'violet',
  'iris',
].map(value => ({
  value,
  headerClass: STAGE_COLOR_CLASSES[value],
  swatchClass: STAGE_COLOR_CLASSES[value],
}));

export const getKanbanStageColorOption = color =>
  KANBAN_STAGE_COLOR_OPTIONS.find(option => option.value === color) ||
  KANBAN_STAGE_COLOR_OPTIONS[0];

export const getKanbanStageColorClass = color =>
  getKanbanStageColorOption(color).headerClass;

export const getKanbanStageBodyColorClass = color =>
  STAGE_BODY_COLOR_CLASSES[getKanbanStageColorOption(color).value];
