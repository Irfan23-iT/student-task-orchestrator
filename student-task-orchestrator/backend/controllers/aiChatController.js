import { supabase } from '../config/supabase.js';
import { isMissingTableError } from '../lib/tableErrors.js';

const MAX_HISTORY_MESSAGES = 20;

const truncateTitle = (text, maxLength = 40) => {
  const cleaned = String(text || '').trim();
  if (cleaned.length <= maxLength) return cleaned;
  return `${cleaned.slice(0, maxLength).trimEnd()}…`;
};

export const createChat = async (req, res) => {
  try {
    const userId = req.user.id;
    const db = req.supabase;
    const title = String(req.body?.title || 'New Chat').trim() || 'New Chat';

    const { data, error } = await db
      .from('ai_chats')
      .insert({ user_id: userId, title })
      .select('id, title, created_at, updated_at')
      .single();

    if (error) throw error;

    res.status(201).json(data);
  } catch (error) {
    const statusCode = Number.isInteger(error?.statusCode) ? error.statusCode : 500;
    console.error('Create AI chat failed:', error.message || error);
    res.status(statusCode).json({
      error: 'Failed to create chat.',
      details: error.message || 'Unknown error.',
    });
  }
};

export const listChats = async (req, res) => {
  try {
    const userId = req.user.id;
    const db = req.supabase;
    const limit = Math.min(Number.parseInt(req.query.limit, 10) || 50, 100);
    const offset = Number.parseInt(req.query.offset, 10) || 0;

    const { data, error } = await db
      .from('ai_chats')
      .select('id, title, created_at, updated_at')
      .eq('user_id', userId)
      .order('updated_at', { ascending: false })
      .range(offset, offset + limit - 1);

    if (error) throw error;

    res.status(200).json({ chats: data || [], limit, offset });
  } catch (error) {
    const statusCode = Number.isInteger(error?.statusCode) ? error.statusCode : 500;
    console.error('List AI chats failed:', error.message || error);
    res.status(statusCode).json({
      error: 'Failed to list chats.',
      details: error.message || 'Unknown error.',
    });
  }
};

export const getChat = async (req, res) => {
  try {
    const userId = req.user.id;
    const db = req.supabase;
    const { chatId } = req.params;

    const { data: chat, error: chatError } = await db
      .from('ai_chats')
      .select('id, title, created_at, updated_at')
      .eq('id', chatId)
      .eq('user_id', userId)
      .single();

    if (chatError) {
      if (chatError.code === 'PGRST116') {
        return res.status(404).json({ error: 'Chat not found.' });
      }
      throw chatError;
    }

    const { data: messages, error: msgError } = await db
      .from('ai_messages')
      .select('id, role, content, action_type, action_performed, created_at')
      .eq('chat_id', chatId)
      .eq('user_id', userId)
      .order('created_at', { ascending: true });

    if (msgError) throw msgError;

    res.status(200).json({ ...chat, messages: messages || [] });
  } catch (error) {
    const statusCode = Number.isInteger(error?.statusCode) ? error.statusCode : 500;
    console.error('Get AI chat failed:', error.message || error);
    res.status(statusCode).json({
      error: 'Failed to get chat.',
      details: error.message || 'Unknown error.',
    });
  }
};

export const deleteChat = async (req, res) => {
  try {
    const userId = req.user.id;
    const db = req.supabase;
    const { chatId } = req.params;

    const { error } = await db
      .from('ai_chats')
      .delete()
      .eq('id', chatId)
      .eq('user_id', userId);

    if (error) throw error;

    res.status(200).json({ deleted: true });
  } catch (error) {
    const statusCode = Number.isInteger(error?.statusCode) ? error.statusCode : 500;
    console.error('Delete AI chat failed:', error.message || error);
    res.status(statusCode).json({
      error: 'Failed to delete chat.',
      details: error.message || 'Unknown error.',
    });
  }
};

export const renameChat = async (req, res) => {
  try {
    const userId = req.user.id;
    const db = req.supabase;
    const { chatId } = req.params;
    const title = String(req.body?.title || '').trim();

    if (!title) {
      return res.status(400).json({ error: 'Title is required.' });
    }

    const { data, error } = await db
      .from('ai_chats')
      .update({ title })
      .eq('id', chatId)
      .eq('user_id', userId)
      .select('id, title, created_at, updated_at')
      .single();

    if (error) {
      if (error.code === 'PGRST116') {
        return res.status(404).json({ error: 'Chat not found.' });
      }
      throw error;
    }

    res.status(200).json(data);
  } catch (error) {
    const statusCode = Number.isInteger(error?.statusCode) ? error.statusCode : 500;
    console.error('Rename AI chat failed:', error.message || error);
    res.status(statusCode).json({
      error: 'Failed to rename chat.',
      details: error.message || 'Unknown error.',
    });
  }
};

export const loadChatHistory = async (db, chatId, userId, limit = MAX_HISTORY_MESSAGES) => {
  const { data, error } = await db
    .from('ai_messages')
    .select('role, content')
    .eq('chat_id', chatId)
    .eq('user_id', userId)
    .order('created_at', { ascending: false })
    .limit(limit);

  if (error) {
    if (isMissingTableError(error, 'ai_messages')) return [];
    throw error;
  }

  return (data || []).reverse();
};

export const saveChatMessage = async (db, { chatId, userId, role, content, actionType, actionPerformed }) => {
  const { data, error } = await db
    .from('ai_messages')
    .insert({
      chat_id: chatId,
      user_id: userId,
      role,
      content,
      action_type: actionType || null,
      action_performed: actionPerformed || false,
    })
    .select('id, role, content, action_type, action_performed, created_at')
    .single();

  if (error) throw error;
  return data;
};

export const autoTitleFromMessage = (message) => truncateTitle(message, 40);
