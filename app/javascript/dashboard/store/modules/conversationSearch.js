import SearchAPI from '../../api/search';
import types from '../mutation-types';
export const initialState = {
  records: [],
  contactRecords: [],
  conversationRecords: [],
  messageRecords: [],
  articleRecords: [],
  uiFlags: {
    isFetching: false,
    isSearchCompleted: false,
    contact: { isFetching: false },
    conversation: { isFetching: false },
    message: { isFetching: false },
    article: { isFetching: false },
  },
};

export const getters = {
  getConversations(state) {
    return state.records;
  },
  getContactRecords(state) {
    return state.contactRecords;
  },
  getConversationRecords(state) {
    return state.conversationRecords;
  },
  getMessageRecords(state) {
    return state.messageRecords;
  },
  getArticleRecords(state) {
    return state.articleRecords;
  },
  getUIFlags(state) {
    return state.uiFlags;
  },
};

// Tracks the most recently dispatched fullSearch call so that a slow
// response from an older, superseded search can be discarded instead of
// being merged into the results of a newer one.
let latestSearchId = 0;

export const actions = {
  async get({ commit }, { q }) {
    commit(types.SEARCH_CONVERSATIONS_SET, []);
    if (!q) {
      return;
    }
    commit(types.SEARCH_CONVERSATIONS_SET_UI_FLAG, { isFetching: true });
    try {
      const {
        data: { payload },
      } = await SearchAPI.get({ q });
      commit(types.SEARCH_CONVERSATIONS_SET, payload);
    } catch (error) {
      // Ignore error
    } finally {
      commit(types.SEARCH_CONVERSATIONS_SET_UI_FLAG, {
        isFetching: false,
      });
    }
  },
  async fullSearch({ commit, dispatch }, payload) {
    const { q, ...filters } = payload;
    if (!q && !Object.keys(filters).length) {
      return;
    }
    latestSearchId += 1;
    const searchId = latestSearchId;
    commit(types.FULL_SEARCH_SET_UI_FLAG, {
      isFetching: true,
      isSearchCompleted: false,
    });
    try {
      await Promise.all([
        dispatch('contactSearch', { q, ...filters, searchId }),
        dispatch('conversationSearch', { q, ...filters, searchId }),
        dispatch('messageSearch', { q, ...filters, searchId }),
        dispatch('articleSearch', { q, ...filters, searchId }),
      ]);
    } catch (error) {
      // Ignore error
    } finally {
      commit(types.FULL_SEARCH_SET_UI_FLAG, {
        isFetching: false,
        isSearchCompleted: true,
      });
    }
  },
  async contactSearch({ commit }, payload) {
    const { page = 1, searchId, ...searchParams } = payload;
    commit(types.CONTACT_SEARCH_SET_UI_FLAG, { isFetching: true });
    try {
      const { data } = await SearchAPI.contacts({ ...searchParams, page });
      if (searchId !== undefined && searchId !== latestSearchId) {
        return;
      }
      commit(types.CONTACT_SEARCH_SET, {
        records: data.payload.contacts,
        page,
      });
    } catch (error) {
      // Ignore error
    } finally {
      commit(types.CONTACT_SEARCH_SET_UI_FLAG, { isFetching: false });
    }
  },
  async conversationSearch({ commit }, payload) {
    const { page = 1, searchId, ...searchParams } = payload;
    commit(types.CONVERSATION_SEARCH_SET_UI_FLAG, { isFetching: true });
    try {
      const { data } = await SearchAPI.conversations({ ...searchParams, page });
      if (searchId !== undefined && searchId !== latestSearchId) {
        return;
      }
      commit(types.CONVERSATION_SEARCH_SET, {
        records: data.payload.conversations,
        page,
      });
    } catch (error) {
      // Ignore error
    } finally {
      commit(types.CONVERSATION_SEARCH_SET_UI_FLAG, { isFetching: false });
    }
  },
  async messageSearch({ commit }, payload) {
    const { page = 1, searchId, ...searchParams } = payload;
    commit(types.MESSAGE_SEARCH_SET_UI_FLAG, { isFetching: true });
    try {
      const { data } = await SearchAPI.messages({ ...searchParams, page });
      if (searchId !== undefined && searchId !== latestSearchId) {
        return;
      }
      commit(types.MESSAGE_SEARCH_SET, {
        records: data.payload.messages,
        page,
      });
    } catch (error) {
      // Ignore error
    } finally {
      commit(types.MESSAGE_SEARCH_SET_UI_FLAG, { isFetching: false });
    }
  },
  async articleSearch({ commit }, payload) {
    const { page = 1, searchId, ...searchParams } = payload;
    commit(types.ARTICLE_SEARCH_SET_UI_FLAG, { isFetching: true });
    try {
      const { data } = await SearchAPI.articles({ ...searchParams, page });
      if (searchId !== undefined && searchId !== latestSearchId) {
        return;
      }
      commit(types.ARTICLE_SEARCH_SET, {
        records: data.payload.articles,
        page,
      });
    } catch (error) {
      // Ignore error
    } finally {
      commit(types.ARTICLE_SEARCH_SET_UI_FLAG, { isFetching: false });
    }
  },
  async clearSearchResults({ commit }) {
    commit(types.CLEAR_SEARCH_RESULTS);
  },
};

export const mutations = {
  [types.SEARCH_CONVERSATIONS_SET](state, records) {
    state.records = records;
  },
  [types.CONTACT_SEARCH_SET](state, { records, page }) {
    state.contactRecords =
      page > 1 ? [...state.contactRecords, ...records] : records;
  },
  [types.CONVERSATION_SEARCH_SET](state, { records, page }) {
    state.conversationRecords =
      page > 1 ? [...state.conversationRecords, ...records] : records;
  },
  [types.MESSAGE_SEARCH_SET](state, { records, page }) {
    state.messageRecords =
      page > 1 ? [...state.messageRecords, ...records] : records;
  },
  [types.ARTICLE_SEARCH_SET](state, { records, page }) {
    state.articleRecords =
      page > 1 ? [...state.articleRecords, ...records] : records;
  },
  [types.SEARCH_CONVERSATIONS_SET_UI_FLAG](state, uiFlags) {
    state.uiFlags = { ...state.uiFlags, ...uiFlags };
  },
  [types.FULL_SEARCH_SET_UI_FLAG](state, uiFlags) {
    state.uiFlags = { ...state.uiFlags, ...uiFlags };
  },
  [types.CONTACT_SEARCH_SET_UI_FLAG](state, uiFlags) {
    state.uiFlags.contact = { ...state.uiFlags.contact, ...uiFlags };
  },
  [types.CONVERSATION_SEARCH_SET_UI_FLAG](state, uiFlags) {
    state.uiFlags.conversation = { ...state.uiFlags.conversation, ...uiFlags };
  },
  [types.MESSAGE_SEARCH_SET_UI_FLAG](state, uiFlags) {
    state.uiFlags.message = { ...state.uiFlags.message, ...uiFlags };
  },
  [types.ARTICLE_SEARCH_SET_UI_FLAG](state, uiFlags) {
    state.uiFlags.article = { ...state.uiFlags.article, ...uiFlags };
  },
  [types.CLEAR_SEARCH_RESULTS](state) {
    state.contactRecords = [];
    state.conversationRecords = [];
    state.messageRecords = [];
    state.articleRecords = [];
  },
};

export default {
  namespaced: true,
  state: initialState,
  getters,
  actions,
  mutations,
};
