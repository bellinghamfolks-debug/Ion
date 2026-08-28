// Runtime configuration validation for EnglishNova.
// Production must fail closed when authentication or database secrets are missing.

export function isProductionEnvironment(env = process.env) {
  return env.NODE_ENV === "production" ||
    Boolean(env.RAILWAY_ENVIRONMENT_ID) ||
    String(env.RAILWAY_ENVIRONMENT_NAME || "").toLowerCase() === "production";
}

export function runtimeConfigStatus(env = process.env) {
  const databaseURL = String(env.DATABASE_URL || "").trim();
  const jwtSecret = String(env.JWT_SECRET || "").trim();
  const googleServerClientID = String(env.GOOGLE_SERVER_CLIENT_ID || "").trim();
  const production = isProductionEnvironment(env);

  return {
    production,
    databaseConfigured: databaseURL.length > 0,
    sessionSecretConfigured: jwtSecret.length >= 32,
    googleConfigured: googleServerClientID.endsWith(".apps.googleusercontent.com"),
  };
}

export function validateRuntimeConfig(env = process.env) {
  const status = runtimeConfigStatus(env);
  const errors = [];

  if (!status.databaseConfigured) {
    errors.push("DATABASE_URL is required");
  }

  if (status.production && !status.sessionSecretConfigured) {
    errors.push("JWT_SECRET must be at least 32 characters in production");
  }

  // Google is a visible production sign-in option in the iOS app, so a hosted
  // production backend must be able to verify its ID tokens.
  if (status.production && !status.googleConfigured) {
    errors.push("GOOGLE_SERVER_CLIENT_ID is required in production");
  }

  return { status, errors };
}

export function assertRuntimeConfig(env = process.env) {
  const result = validateRuntimeConfig(env);
  if (result.errors.length > 0) {
    const error = new Error(`Invalid EnglishNova runtime configuration: ${result.errors.join("; ")}`);
    error.code = "invalid_runtime_configuration";
    throw error;
  }
  return result.status;
}
