module.exports = {
  extends: ["@salesforce/eslint-config-lwc/recommended"],
  parserOptions: {
    ecmaVersion: 2020,
    sourceType: "module"
  },
  plugins: ["@lwc/eslint-plugin-lwc"],
  rules: {
    // Add any custom rules here
  },
  env: {
    browser: true,
    es2020: true
  },
  overrides: [
    {
      files: ["*.test.js"],
      env: {
        jest: true
      },
      plugins: ["jest"]
    }
  ]
};
