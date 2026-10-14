// Groups the raw WAHA status history (oldest first) for display: newest day
// first, and consecutive identical statuses within a day collapsed into one
// entry that keeps how many times it happened and its first/last timestamp.
export const groupConnectionLog = history => {
  const days = [];
  [...history].reverse().forEach(event => {
    const day = new Date(event.timestamp).toDateString();
    let group = days[days.length - 1];
    if (group?.day !== day) {
      group = { day, timestamp: event.timestamp, entries: [] };
      days.push(group);
    }

    const last = group.entries[group.entries.length - 1];
    if (last?.status === event.status) {
      last.count += 1;
      last.firstAt = event.timestamp;
    } else {
      group.entries.push({
        status: event.status,
        count: 1,
        firstAt: event.timestamp,
        lastAt: event.timestamp,
      });
    }
  });
  return days;
};
