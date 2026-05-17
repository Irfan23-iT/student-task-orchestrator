export const isMissingTableError = (error, tableName = '') => {
  if (!error) return false;

  const code = `${error.code || ''}`.toUpperCase().trim();
  const message = `${error.message || error.details || ''}`.toLowerCase();
  const normalizedTableName = `${tableName || ''}`.toLowerCase();

  if (code === 'PGRST205' || code === '42P01') return true;
  if (normalizedTableName && message.includes(normalizedTableName) && message.includes('schema cache')) {
    return true;
  }

  return message.includes('could not find the table');
};
