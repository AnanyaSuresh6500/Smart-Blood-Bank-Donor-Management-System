import axios from 'axios';

// Base URL points to our Express backend
const api = axios.create({
  baseURL: 'http://localhost:5000',
});

// Before every request — attach the access token from localStorage
api.interceptors.request.use((config) => {
  const token = localStorage.getItem('accessToken');
  if (token) config.headers.Authorization = `Bearer ${token}`;
  return config;
});

// After every response — if token expired (401), try to refresh it
api.interceptors.response.use(
  (res) => res,
  async (err) => {
    if (err.response?.status === 401) {
      try {
        const { data } = await axios.post('http://localhost:5000/auth/refresh', {
          refreshToken: localStorage.getItem('refreshToken'),
        });
        // Save new access token and retry the original request
        localStorage.setItem('accessToken', data.accessToken);
        err.config.headers.Authorization = `Bearer ${data.accessToken}`;
        return api(err.config);
      } catch {
        // Refresh token also expired — force logout
        localStorage.clear();
        window.location.href = '/login';
      }
    }
    return Promise.reject(err);
  }
);

export default api;