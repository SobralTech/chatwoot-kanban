/* global axios */
import ApiClient from './ApiClient';

class AccountAPI extends ApiClient {
  constructor() {
    super('', { accountScoped: true });
  }

  createAccount(data) {
    return axios.post(`${this.apiVersion}/accounts`, data);
  }

  async getCacheKeys() {
    const response = await axios.get(
      `/api/v1/accounts/${this.accountIdFromRoute}/cache_keys`
    );
    return response.data.cache_keys;
  }

  getBranding() {
    return axios.get(`${this.baseUrl()}/branding`);
  }

  updateBranding({ assetName, file }) {
    const formData = new FormData();
    formData.append('asset_name', assetName);
    formData.append('file', file);

    return axios.patch(`${this.baseUrl()}/branding`, formData);
  }

  deleteBranding(assetName) {
    return axios.delete(`${this.baseUrl()}/branding/${assetName}`);
  }
}

export default new AccountAPI();
