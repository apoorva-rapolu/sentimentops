// API base URL = the Terraform output `api_base_url` (contract section 7).
// Leave empty to run in MOCK mode (no backend needed).
// The deploy workflow overwrites this file with the real URL before syncing to S3.
window.SENTIMENTOPS_CONFIG = {
  API_BASE_URL: "",
};
