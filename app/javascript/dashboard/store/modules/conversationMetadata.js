import * as types from '../mutation-types';

const state = {
  records: {},
};

export const getters = {
  getConversationMetadata: $state => id => {
    return $state.records[Number(id)] || {};
  },
};

export const actions = {};

export const mutations = {
  [types.default.SET_CONVERSATION_METADATA]: ($state, { id, data }) => {
    $state.records = { ...$state.records, [id]: data };
  },
  [types.default.CLEAR_CONVERSATION_METADATA]: ($state, id) => {
    const { [id]: removedRecord, ...remainingRecords } = $state.records;
    $state.records = remainingRecords;
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
