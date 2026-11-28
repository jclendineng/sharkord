// a settings form is dirty by value, not by identity: a toggle flipped back to its original state,
// or a rebuilt array holding the same members, counts as clean
const hasUnsavedChanges = (values: unknown, baseline: unknown) =>
  JSON.stringify(values) !== JSON.stringify(baseline);

// the sidebar's search, the apps' too: pages whose name has the typed text in it, any case
const filterEntries = <T extends { label: string }>(
  entries: T[],
  query: string
) => {
  const text = query.trim().toLowerCase();

  if (!text) {
    return entries;
  }

  return entries.filter((entry) => entry.label.toLowerCase().includes(text));
};

export { filterEntries, hasUnsavedChanges };
