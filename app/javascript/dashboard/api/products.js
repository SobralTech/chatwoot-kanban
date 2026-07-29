/* global axios */
import ApiClient from './ApiClient';

class ProductsAPI extends ApiClient {
  constructor() {
    super('products', { accountScoped: true });
  }

  search(params = {}) {
    return axios.get(`${this.url}/search`, { params });
  }
}

export default new ProductsAPI();
