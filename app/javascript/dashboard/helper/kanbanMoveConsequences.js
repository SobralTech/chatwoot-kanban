const valueFor = (record, camelKey, snakeKey) =>
  record?.[camelKey] ?? record?.[snakeKey];

const customFieldsFor = board =>
  valueFor(board, 'customFields', 'custom_fields') || [];

const fieldMatches = (sourceField, targetField) =>
  targetField.key === sourceField.key &&
  targetField.fieldType === sourceField.fieldType &&
  Boolean(targetField.multiple) === Boolean(sourceField.multiple);

export const getKanbanMoveConsequences = ({
  card = {},
  sourceBoard = {},
  targetBoard = {},
  reasons = [],
}) => {
  const sourceStageId = Number(
    valueFor(card, 'kanbanStageId', 'kanban_stage_id') ??
      card?.kanbanStage?.id ??
      card?.kanban_stage?.id
  );
  const sourceWonStageId = Number(
    valueFor(sourceBoard, 'wonStageId', 'won_stage_id')
  );
  const sourceLostStageId = Number(
    valueFor(sourceBoard, 'lostStageId', 'lost_stage_id')
  );
  const consequences = [];

  if ([sourceWonStageId, sourceLostStageId].includes(sourceStageId)) {
    consequences.push({ key: 'MOVE_CONFIRM_REOPEN', params: {} });
  }

  const reasonId = Number(valueFor(card, 'kanbanReasonId', 'kanban_reason_id'));
  if (reasonId) {
    const reason = reasons.find(item => Number(item.id) === reasonId);
    consequences.push({
      key: 'MOVE_CONFIRM_REASON',
      params: { reason: reason?.title || reasonId },
    });
  }

  const cardCustomFieldKeys = (
    valueFor(card, 'customFieldKeys', 'custom_field_keys') || []
  ).filter(Boolean);
  const sourceCustomFields = customFieldsFor(sourceBoard);
  const targetCustomFields = customFieldsFor(targetBoard);
  const droppedFieldKeys = cardCustomFieldKeys.filter(key => {
    const sourceField = sourceCustomFields.find(field => field.key === key);
    if (!sourceField) return true;

    return !targetCustomFields.some(targetField =>
      fieldMatches(sourceField, targetField)
    );
  });

  if (droppedFieldKeys.length) {
    consequences.push({
      key: 'MOVE_CONFIRM_FIELDS',
      params: {
        count: droppedFieldKeys.length,
        total: cardCustomFieldKeys.length,
        board: targetBoard?.name || '',
        keys: droppedFieldKeys.join(', '),
      },
    });
  }

  const isTerminal = [sourceWonStageId, sourceLostStageId].includes(
    sourceStageId
  );
  const wonRecurrenceEnabled = Boolean(
    valueFor(sourceBoard, 'wonRecurrenceEnabled', 'won_recurrence_enabled')
  );
  const lostRecurrenceEnabled = Boolean(
    valueFor(sourceBoard, 'lostRecurrenceEnabled', 'lost_recurrence_enabled')
  );
  const recurrenceEnabledForSourceStage =
    (sourceStageId === sourceWonStageId && wonRecurrenceEnabled) ||
    (sourceStageId === sourceLostStageId && lostRecurrenceEnabled);
  const sourceBoardName = sourceBoard?.name || '';

  if (isTerminal && recurrenceEnabledForSourceStage) {
    consequences.push({
      key: 'MOVE_CONFIRM_RECURRENCE_REFERENCE_LEAVES',
      params: { board: sourceBoardName },
    });
  } else if (!isTerminal && (wonRecurrenceEnabled || lostRecurrenceEnabled)) {
    consequences.push({
      key: 'MOVE_CONFIRM_RECURRENCE_MAY_RECREATE',
      params: { board: sourceBoardName },
    });
  }

  return consequences;
};

export default getKanbanMoveConsequences;
