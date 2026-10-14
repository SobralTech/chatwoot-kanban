/* global axios */
import CacheEnabledApiClient from './CacheEnabledApiClient';

const buildPayload = data => {
  if (!data.steps) {
    return data;
  }

  const payload = new FormData();
  payload.append('canned_response[short_code]', data.short_code);
  payload.append('canned_response[content]', data.content || '');
  payload.append('canned_response[mode]', data.mode || 'insert');

  const steps = data.steps.map((step, index) => {
    const fileKey = step.file ? `step_${index}` : undefined;
    if (fileKey) {
      payload.append(`step_files[${fileKey}]`, step.file);
    }

    return {
      step_type: step.step_type,
      content: step.content || '',
      position: index,
      file_key: fileKey,
      file_blob_id: step.file_blob_id,
    };
  });

  payload.append('canned_response[steps]', JSON.stringify(steps));
  return payload;
};

class CannedResponse extends CacheEnabledApiClient {
  constructor() {
    super('canned_responses', { accountScoped: true });
  }

  // eslint-disable-next-line class-methods-use-this
  get cacheModelName() {
    return 'canned_response';
  }

  // The index endpoint returns a bare array instead of a payload wrapper
  // eslint-disable-next-line class-methods-use-this
  extractDataFromResponse(response) {
    return response.data;
  }

  // eslint-disable-next-line class-methods-use-this
  marshallData(dataToParse) {
    return { data: dataToParse };
  }

  create(data) {
    return axios.post(this.url, buildPayload(data));
  }

  update(id, data) {
    return axios.patch(`${this.url}/${id}`, buildPayload(data));
  }

  send({ id, conversationId }) {
    return axios.post(`${this.url}/${id}/send_response`, {
      conversation_id: conversationId,
    });
  }
}

export default new CannedResponse();
