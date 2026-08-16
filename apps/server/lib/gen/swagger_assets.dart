// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Embedded OpenAPI specs for compiled Zonai builds.
//
// Regenerate:
//   dart run tool/generate_swagger_assets.dart

library;

const kSwaggerJson = r'''{
  "openapi": "3.0.3",
  "info": {
    "title": "API",
    "version": "1.0.0"
  },
  "paths": {
    "/admin/invites": {
      "post": {
        "operationId": "admin_invite",
        "tags": [
          "admin"
        ],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "$ref": "#/components/schemas/AdminInviteBody"
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "`{email, table, expiresAt, isResend}`"
          },
          "403": {
            "description": "No Bearer token, or one that is not an admin for the resolved `AsAdmin` table"
          },
          "429": {
            "description": "adminInvite rate limit exceeded, or this address was already invited within the last minute"
          }
        }
      }
    },
    "/admin/invites/{email}": {
      "delete": {
        "operationId": "admin_revokeInvite",
        "tags": [
          "admin"
        ],
        "parameters": [
          {
            "name": "email",
            "in": "path",
            "required": true,
            "schema": {
              "type": "string"
            }
          }
        ],
        "responses": {
          "403": {
            "description": "No Bearer token, or one that is not an admin for the resolved `AsAdmin` table"
          }
        }
      }
    },
    "/admin/members": {
      "get": {
        "operationId": "admin_members",
        "tags": [
          "admin"
        ],
        "responses": {
          "200": {
            "description": "`{admins: [...], invites: [{email, invitedAt, expiresAt, invitedByEmail}]}`"
          },
          "403": {
            "description": "No Bearer token, or one that is not an admin for the resolved `AsAdmin` table"
          }
        }
      }
    },
    "/admin/members/{email}": {
      "delete": {
        "operationId": "admin_removeMember",
        "tags": [
          "admin"
        ],
        "parameters": [
          {
            "name": "email",
            "in": "path",
            "required": true,
            "schema": {
              "type": "string"
            }
          }
        ],
        "responses": {
          "200": {
            "description": "The removed admin row, sanitized"
          },
          "403": {
            "description": "No Bearer token, one that is not an admin for the resolved `AsAdmin` table, or an admin removing themselves"
          },
          "409": {
            "description": "That is the table's last admin"
          }
        }
      }
    },
    "/auth": {
      "delete": {
        "operationId": "auth_logout",
        "tags": [
          "auth"
        ],
        "responses": {
          "200": {
            "description": "No content"
          }
        }
      },
      "post": {
        "operationId": "auth_authenticate",
        "tags": [
          "auth"
        ],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "$ref": "#/components/schemas/AuthBody"
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Success",
            "content": {
              "application/json": {
                "schema": {
                  "type": "object",
                  "additionalProperties": true,
                  "nullable": true
                }
              }
            }
          }
        }
      }
    },
    "/auth/admin": {
      "post": {
        "operationId": "auth_adminAuthenticate",
        "tags": [
          "auth"
        ],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "$ref": "#/components/schemas/AdminAuthBody"
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Success",
            "content": {
              "application/json": {
                "schema": {
                  "type": "object",
                  "additionalProperties": true,
                  "nullable": true
                }
              }
            }
          }
        }
      }
    },
    "/auth/admin/invite": {
      "get": {
        "operationId": "auth_adminInviteStatus",
        "tags": [
          "auth"
        ],
        "parameters": [
          {
            "name": "token",
            "in": "query",
            "required": true,
            "schema": {
              "type": "string"
            }
          }
        ],
        "responses": {
          "200": {
            "description": "`{live: true, table, authTypes}` when the token names an invite that can still be accepted, and `{live: false}` for every token that cannot -- expired, revoked, already accepted or unknown alike, deliberately indistinguishable. Never the invited email."
          },
          "429": {
            "description": "oauthInviteStart rate limit exceeded"
          }
        }
      }
    },
    "/auth/admin/invite/oauth/start/{provider}": {
      "get": {
        "operationId": "auth_startAdminInviteOAuth",
        "tags": [
          "auth"
        ],
        "parameters": [
          {
            "name": "provider",
            "in": "path",
            "required": true,
            "schema": {
              "type": "string"
            }
          },
          {
            "name": "token",
            "in": "query",
            "required": true,
            "schema": {
              "type": "string"
            }
          },
          {
            "name": "redirect_to",
            "in": "query",
            "required": false,
            "schema": {
              "type": "string",
              "nullable": true
            }
          }
        ],
        "responses": {
          "302": {
            "description": "Redirect to the provider's authorization endpoint. Carries `state` and `code_challenge` in the Location header."
          },
          "400": {
            "description": "`redirect_to` is neither a relative path nor this app's own origin"
          },
          "401": {
            "description": "The invite token names no live invite, or it has expired"
          },
          "404": {
            "description": "No admin collection is configured for OAuth sign-in, or it has no such provider"
          },
          "429": {
            "description": "oauthStart rate limit exceeded"
          }
        }
      }
    },
    "/auth/admin/oauth/start/{provider}": {
      "get": {
        "operationId": "auth_startAdminOAuth",
        "tags": [
          "auth"
        ],
        "parameters": [
          {
            "name": "provider",
            "in": "path",
            "required": true,
            "schema": {
              "type": "string"
            }
          },
          {
            "name": "redirect_to",
            "in": "query",
            "required": false,
            "schema": {
              "type": "string",
              "nullable": true
            }
          }
        ],
        "responses": {
          "302": {
            "description": "Redirect to the provider's authorization endpoint. Carries `state` and `code_challenge` in the Location header."
          },
          "400": {
            "description": "`redirect_to` is neither a relative path nor this app's own origin"
          },
          "404": {
            "description": "No admin collection is configured for OAuth sign-in, or it has no such provider"
          },
          "429": {
            "description": "oauthStart rate limit exceeded"
          }
        }
      }
    },
    "/auth/all": {
      "delete": {
        "operationId": "auth_logoutAll",
        "tags": [
          "auth"
        ],
        "responses": {
          "200": {
            "description": "No content"
          }
        }
      }
    },
    "/auth/confirm": {
      "post": {
        "operationId": "auth_confirm",
        "tags": [
          "auth"
        ],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "$ref": "#/components/schemas/VerifyAuthBody"
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Success",
            "content": {
              "application/json": {
                "schema": {
                  "type": "object",
                  "additionalProperties": true,
                  "nullable": true
                }
              }
            }
          }
        }
      }
    },
    "/auth/oauth": {
      "post": {
        "operationId": "auth_oauth",
        "tags": [
          "auth"
        ],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "$ref": "#/components/schemas/OAuthBody"
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Success",
            "content": {
              "application/json": {
                "schema": {
                  "type": "object",
                  "additionalProperties": true
                }
              }
            }
          }
        }
      }
    },
    "/auth/oauth/callback/{provider}": {
      "get": {
        "operationId": "auth_oauthCallback",
        "tags": [
          "auth"
        ],
        "parameters": [
          {
            "name": "provider",
            "in": "path",
            "required": true,
            "schema": {
              "type": "string"
            }
          },
          {
            "name": "code",
            "in": "query",
            "required": false,
            "schema": {
              "type": "string",
              "nullable": true
            }
          },
          {
            "name": "state",
            "in": "query",
            "required": false,
            "schema": {
              "type": "string",
              "nullable": true
            }
          },
          {
            "name": "error",
            "in": "query",
            "required": false,
            "schema": {
              "type": "string",
              "nullable": true
            }
          }
        ],
        "responses": {
          "302": {
            "description": "Session minted; redirect to the `redirect_to` recorded at start"
          },
          "400": {
            "description": "Provider returned `error`, or the callback carried no usable `code`/`state`"
          },
          "401": {
            "description": "Unknown, replayed or expired `state`"
          },
          "429": {
            "description": "oauthCallback rate limit exceeded"
          }
        }
      },
      "post": {
        "operationId": "auth_oauthCallbackFormPost",
        "tags": [
          "auth"
        ],
        "parameters": [
          {
            "name": "provider",
            "in": "path",
            "required": true,
            "schema": {
              "type": "string"
            }
          }
        ],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "$ref": "#/components/schemas/OAuthCallbackBody"
              }
            }
          }
        },
        "responses": {
          "302": {
            "description": "Session minted; redirect to the `redirect_to` recorded at start"
          },
          "400": {
            "description": "Provider returned `error`, or the callback carried no usable `code`/`state`"
          },
          "401": {
            "description": "Unknown, replayed or expired `state`"
          },
          "429": {
            "description": "oauthCallback rate limit exceeded"
          }
        }
      }
    },
    "/auth/oauth/providers": {
      "get": {
        "operationId": "auth_oauthProviders",
        "tags": [
          "auth"
        ],
        "parameters": [
          {
            "name": "table",
            "in": "query",
            "required": false,
            "schema": {
              "type": "string",
              "nullable": true
            }
          }
        ],
        "responses": {
          "200": {
            "description": "Success",
            "content": {
              "application/json": {
                "schema": {
                  "type": "array",
                  "items": {
                    "type": "object",
                    "additionalProperties": true
                  }
                }
              }
            }
          }
        }
      }
    },
    "/auth/oauth/start/{provider}": {
      "get": {
        "operationId": "auth_startOAuth",
        "tags": [
          "auth"
        ],
        "parameters": [
          {
            "name": "provider",
            "in": "path",
            "required": true,
            "schema": {
              "type": "string"
            }
          },
          {
            "name": "table",
            "in": "query",
            "required": true,
            "schema": {
              "type": "string"
            }
          },
          {
            "name": "redirect_to",
            "in": "query",
            "required": false,
            "schema": {
              "type": "string",
              "nullable": true
            }
          }
        ],
        "responses": {
          "302": {
            "description": "Redirect to the provider's authorization endpoint. Carries `state` and `code_challenge` in the Location header."
          },
          "400": {
            "description": "`redirect_to` is neither a relative path nor this app's own origin"
          },
          "404": {
            "description": "No such provider on that table"
          },
          "429": {
            "description": "oauthStart rate limit exceeded"
          }
        }
      }
    },
    "/auth/refresh": {
      "post": {
        "operationId": "auth_refreshToken",
        "tags": [
          "auth"
        ],
        "responses": {
          "200": {
            "description": "Success",
            "content": {
              "application/json": {
                "schema": {
                  "type": "object",
                  "additionalProperties": true,
                  "nullable": true
                }
              }
            }
          }
        }
      }
    },
    "/auth/reset-password": {
      "post": {
        "operationId": "auth_sendResetPassword",
        "tags": [
          "auth"
        ],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "$ref": "#/components/schemas/ResetPasswordAuthBody"
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "No content"
          }
        }
      }
    },
    "/auth/sign-in": {
      "post": {
        "operationId": "auth_signIn",
        "tags": [
          "auth"
        ],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "$ref": "#/components/schemas/SignInAuthBody"
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Success",
            "content": {
              "application/json": {
                "schema": {
                  "type": "object",
                  "additionalProperties": true
                }
              }
            }
          }
        }
      }
    },
    "/auth/sign-up": {
      "post": {
        "operationId": "auth_signUp",
        "tags": [
          "auth"
        ],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "$ref": "#/components/schemas/SignUpAuthBody"
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Success",
            "content": {
              "application/json": {
                "schema": {
                  "type": "object",
                  "additionalProperties": true
                }
              }
            }
          }
        }
      }
    },
    "/auth/verify-email": {
      "post": {
        "operationId": "auth_sendVerifyEmail",
        "tags": [
          "auth"
        ],
        "requestBody": {
          "required": false,
          "content": {
            "application/json": {
              "schema": {
                "allOf": [
                  {
                    "$ref": "#/components/schemas/VerifyEmailAuthBody"
                  }
                ],
                "nullable": true
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "No content"
          }
        }
      }
    },
    "/crons/list": {
      "get": {
        "operationId": "cron_list",
        "tags": [
          "cron"
        ],
        "responses": {
          "200": {
            "description": "Success",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/CronJobList"
                }
              }
            }
          }
        }
      }
    },
    "/crons/run": {
      "post": {
        "operationId": "cron_run",
        "tags": [
          "cron"
        ],
        "parameters": [
          {
            "name": "name",
            "in": "query",
            "required": true,
            "schema": {
              "type": "string"
            }
          }
        ],
        "responses": {
          "200": {
            "description": "No content"
          }
        }
      }
    },
    "/dashboard/metrics": {
      "get": {
        "operationId": "dashboard_metrics",
        "tags": [
          "dashboard"
        ],
        "parameters": [
          {
            "name": "since",
            "in": "query",
            "required": false,
            "schema": {
              "type": "integer",
              "format": "int64",
              "nullable": true
            }
          },
          {
            "name": "exclude_admin",
            "in": "query",
            "required": false,
            "schema": {
              "type": "boolean",
              "nullable": true
            }
          }
        ],
        "responses": {
          "200": {
            "description": "Success",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/DashboardMetrics"
                }
              }
            }
          }
        }
      }
    },
    "/db": {
      "delete": {
        "operationId": "db_delete",
        "tags": [
          "db"
        ],
        "parameters": [
          {
            "name": "body",
            "in": "query",
            "required": true,
            "schema": {
              "$ref": "#/components/schemas/DeleteOneBody"
            }
          }
        ],
        "responses": {
          "200": {
            "description": "No content"
          }
        }
      },
      "get": {
        "operationId": "db_get",
        "tags": [
          "db"
        ],
        "parameters": [
          {
            "name": "body",
            "in": "query",
            "required": true,
            "schema": {
              "$ref": "#/components/schemas/GetBody"
            }
          }
        ],
        "responses": {
          "200": {
            "description": "Success",
            "content": {
              "application/json": {
                "schema": {
                  "type": "object",
                  "additionalProperties": true
                }
              }
            }
          }
        }
      },
      "patch": {
        "operationId": "db_update",
        "tags": [
          "db"
        ],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "$ref": "#/components/schemas/UpdateOneBody"
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Success",
            "content": {
              "application/json": {
                "schema": {
                  "type": "object",
                  "additionalProperties": true
                }
              }
            }
          }
        }
      },
      "post": {
        "operationId": "db_create",
        "tags": [
          "db"
        ],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "$ref": "#/components/schemas/CreateBody"
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Success",
            "content": {
              "application/json": {
                "schema": {
                  "type": "object",
                  "additionalProperties": true
                }
              }
            }
          }
        }
      }
    },
    "/db/count": {
      "get": {
        "operationId": "db_count",
        "tags": [
          "db"
        ],
        "parameters": [
          {
            "name": "body",
            "in": "query",
            "required": true,
            "schema": {
              "$ref": "#/components/schemas/CountBody"
            }
          }
        ],
        "responses": {
          "200": {
            "description": "Success",
            "content": {
              "application/json": {
                "schema": {
                  "type": "integer",
                  "format": "int64"
                }
              }
            }
          }
        }
      }
    },
    "/db/custom/{operation}": {
      "patch": {
        "operationId": "db_custom",
        "tags": [
          "db"
        ],
        "parameters": [
          {
            "name": "operation",
            "in": "path",
            "required": true,
            "schema": {
              "type": "string"
            }
          }
        ],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "$ref": "#/components/schemas/CustomOneBody"
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Success",
            "content": {
              "application/json": {
                "schema": {
                  "type": "object",
                  "additionalProperties": true
                }
              }
            }
          }
        }
      }
    },
    "/db/custom/{operation}/many": {
      "patch": {
        "operationId": "db_customMany",
        "tags": [
          "db"
        ],
        "parameters": [
          {
            "name": "operation",
            "in": "path",
            "required": true,
            "schema": {
              "type": "string"
            }
          }
        ],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "$ref": "#/components/schemas/CustomBody"
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Success",
            "content": {
              "application/json": {
                "schema": {
                  "type": "array",
                  "items": {
                    "type": "object",
                    "additionalProperties": true
                  }
                }
              }
            }
          }
        }
      }
    },
    "/db/list": {
      "get": {
        "operationId": "db_list",
        "tags": [
          "db"
        ],
        "parameters": [
          {
            "name": "body",
            "in": "query",
            "required": true,
            "schema": {
              "$ref": "#/components/schemas/ListBody"
            }
          }
        ],
        "responses": {
          "200": {
            "description": "Success",
            "content": {
              "application/json": {
                "schema": {
                  "type": "object",
                  "additionalProperties": true
                }
              }
            }
          }
        }
      }
    },
    "/db/many": {
      "delete": {
        "operationId": "db_deleteMany",
        "tags": [
          "db"
        ],
        "parameters": [
          {
            "name": "body",
            "in": "query",
            "required": true,
            "schema": {
              "$ref": "#/components/schemas/DeleteBody"
            }
          }
        ],
        "responses": {
          "200": {
            "description": "No content"
          }
        }
      },
      "patch": {
        "operationId": "db_updateMany",
        "tags": [
          "db"
        ],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "$ref": "#/components/schemas/UpdateBody"
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Success",
            "content": {
              "application/json": {
                "schema": {
                  "type": "array",
                  "items": {
                    "type": "object",
                    "additionalProperties": true
                  }
                }
              }
            }
          }
        }
      },
      "post": {
        "operationId": "db_createMany",
        "tags": [
          "db"
        ],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "$ref": "#/components/schemas/CreateManyBody"
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Success",
            "content": {
              "application/json": {
                "schema": {
                  "type": "array",
                  "items": {
                    "type": "object",
                    "additionalProperties": true
                  }
                }
              }
            }
          }
        }
      }
    },
    "/db/stream": {
      "get": {
        "operationId": "db_streamOne",
        "tags": [
          "db"
        ],
        "parameters": [
          {
            "name": "body",
            "in": "query",
            "required": true,
            "schema": {
              "$ref": "#/components/schemas/StreamBody"
            }
          }
        ],
        "responses": {
          "200": {
            "description": "Success",
            "content": {
              "application/json": {
                "schema": {
                  "type": "object",
                  "additionalProperties": true
                }
              }
            }
          }
        }
      }
    },
    "/db/stream/count": {
      "get": {
        "operationId": "db_streamCount",
        "tags": [
          "db"
        ],
        "parameters": [
          {
            "name": "body",
            "in": "query",
            "required": true,
            "schema": {
              "$ref": "#/components/schemas/StreamCountBody"
            }
          }
        ],
        "responses": {
          "200": {
            "description": "Success",
            "content": {
              "application/json": {
                "schema": {
                  "type": "integer",
                  "format": "int64"
                }
              }
            }
          }
        }
      }
    },
    "/db/stream/list": {
      "get": {
        "operationId": "db_streamList",
        "tags": [
          "db"
        ],
        "parameters": [
          {
            "name": "body",
            "in": "query",
            "required": true,
            "schema": {
              "$ref": "#/components/schemas/StreamListBody"
            }
          }
        ],
        "responses": {
          "200": {
            "description": "Success",
            "content": {
              "application/json": {
                "schema": {
                  "type": "array",
                  "items": {
                    "type": "object",
                    "additionalProperties": true
                  }
                }
              }
            }
          }
        }
      }
    },
    "/email": {
      "post": {
        "operationId": "email_send",
        "tags": [
          "email"
        ],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "$ref": "#/components/schemas/Email"
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "No content"
          }
        }
      }
    },
    "/health": {
      "get": {
        "operationId": "root_health",
        "tags": [
          "root"
        ],
        "responses": {
          "200": {
            "description": "No content"
          }
        }
      }
    },
    "/img": {
      "post": {
        "operationId": "photos_create",
        "tags": [
          "photos"
        ],
        "parameters": [
          {
            "name": "meta",
            "in": "query",
            "required": true,
            "schema": {
              "$ref": "#/components/schemas/PhotoCreateMeta"
            }
          }
        ],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "array",
                "items": {
                  "type": "integer",
                  "format": "int64"
                }
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Success",
            "content": {
              "application/json": {
                "schema": {
                  "type": "object",
                  "additionalProperties": true
                }
              }
            }
          }
        }
      }
    },
    "/img/{id}": {
      "delete": {
        "operationId": "photos_delete",
        "tags": [
          "photos"
        ],
        "parameters": [
          {
            "name": "id",
            "in": "path",
            "required": true,
            "schema": {
              "type": "string"
            }
          }
        ],
        "responses": {
          "200": {
            "description": "No content"
          }
        }
      },
      "get": {
        "operationId": "photos_view",
        "tags": [
          "photos"
        ],
        "parameters": [
          {
            "name": "id",
            "in": "path",
            "required": true,
            "schema": {
              "type": "string"
            }
          }
        ],
        "responses": {
          "200": {
            "description": "Success",
            "content": {
              "application/json": {
                "schema": {
                  "type": "array",
                  "items": {
                    "type": "integer",
                    "format": "int64"
                  }
                }
              }
            }
          }
        }
      },
      "patch": {
        "operationId": "photos_update",
        "tags": [
          "photos"
        ],
        "parameters": [
          {
            "name": "id",
            "in": "path",
            "required": true,
            "schema": {
              "type": "string"
            }
          }
        ],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "array",
                "items": {
                  "type": "integer",
                  "format": "int64"
                }
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "No content"
          }
        }
      }
    },
    "/swagger.json": {
      "get": {
        "operationId": "root_swaggerJson",
        "tags": [
          "root"
        ],
        "responses": {
          "200": {
            "description": "Success",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/StringContent"
                }
              }
            }
          }
        }
      }
    },
    "/swagger.yaml": {
      "get": {
        "operationId": "root_swaggerYaml",
        "tags": [
          "root"
        ],
        "responses": {
          "200": {
            "description": "Success",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/StringContent"
                }
              }
            }
          }
        }
      }
    }
  },
  "components": {
    "schemas": {
      "Add": {
        "type": "object",
        "properties": {
          "value": {
            "nullable": true
          }
        }
      },
      "AddAll": {
        "type": "object",
        "properties": {
          "values": {
            "type": "array",
            "items": {
              "nullable": true
            }
          }
        },
        "required": [
          "values"
        ]
      },
      "AdminAuthBody": {
        "type": "object",
        "properties": {
          "type": {
            "type": "string"
          }
        },
        "required": [
          "type"
        ]
      },
      "AdminInviteBody": {
        "type": "object",
        "properties": {
          "email": {
            "type": "string"
          }
        },
        "required": [
          "email"
        ]
      },
      "AdminSendResetPasswordAuthBody": {
        "type": "object",
        "properties": {
          "type": {
            "type": "string"
          },
          "email": {
            "type": "string"
          }
        },
        "required": [
          "type",
          "email"
        ]
      },
      "And": {
        "type": "object",
        "properties": {
          "conditions": {
            "type": "array",
            "items": {
              "$ref": "#/components/schemas/Where"
            }
          }
        },
        "required": [
          "conditions"
        ]
      },
      "AuthBody": {
        "oneOf": [
          {
            "$ref": "#/components/schemas/SendOtpAuthBody"
          },
          {
            "$ref": "#/components/schemas/SendMagicLinkAuthBody"
          },
          {
            "$ref": "#/components/schemas/SignInAuthBody"
          },
          {
            "$ref": "#/components/schemas/SignUpAuthBody"
          }
        ]
      },
      "ColumnUpdate": {
        "type": "object",
        "properties": {
          "column": {
            "type": "string"
          },
          "value": {
            "$ref": "#/components/schemas/UpdateValue"
          }
        },
        "required": [
          "column",
          "value"
        ]
      },
      "ConfirmResetPasswordAuthBody": {
        "type": "object",
        "properties": {
          "token": {
            "type": "string"
          },
          "newPassword": {
            "type": "string"
          },
          "type": {
            "type": "string"
          }
        },
        "required": [
          "token",
          "newPassword",
          "type"
        ]
      },
      "ConfirmVerifyEmailAuthBody": {
        "type": "object",
        "properties": {
          "token": {
            "type": "string"
          },
          "type": {
            "type": "string"
          }
        },
        "required": [
          "token",
          "type"
        ]
      },
      "Contains": {
        "type": "object",
        "properties": {
          "column": {
            "type": "string"
          },
          "value": {}
        },
        "required": [
          "column",
          "value"
        ]
      },
      "CountBody": {
        "type": "object",
        "properties": {
          "table": {
            "type": "string"
          },
          "where": {
            "allOf": [
              {
                "$ref": "#/components/schemas/Where"
              }
            ],
            "nullable": true
          }
        },
        "required": [
          "table"
        ]
      },
      "CreateBody": {
        "type": "object",
        "properties": {
          "table": {
            "type": "string"
          },
          "object": {
            "type": "object",
            "additionalProperties": true
          }
        },
        "required": [
          "table",
          "object"
        ]
      },
      "CreateManyBody": {
        "type": "object",
        "properties": {
          "table": {
            "type": "string"
          },
          "objects": {
            "type": "array",
            "items": {
              "type": "object",
              "additionalProperties": true
            }
          }
        },
        "required": [
          "table",
          "objects"
        ]
      },
      "CronJobList": {
        "type": "object",
        "properties": {
          "names": {
            "type": "array",
            "items": {
              "type": "string"
            }
          }
        },
        "required": [
          "names"
        ]
      },
      "CustomBody": {
        "type": "object",
        "properties": {
          "table": {
            "type": "string"
          },
          "where": {
            "allOf": [
              {
                "$ref": "#/components/schemas/Where"
              }
            ],
            "nullable": true
          },
          "limit": {
            "type": "integer",
            "format": "int64",
            "nullable": true
          },
          "updates": {
            "type": "array",
            "items": {
              "$ref": "#/components/schemas/Update"
            }
          }
        },
        "required": [
          "table",
          "updates"
        ]
      },
      "CustomOneBody": {
        "type": "object",
        "properties": {
          "table": {
            "type": "string"
          },
          "where": {
            "allOf": [
              {
                "$ref": "#/components/schemas/Where"
              }
            ],
            "nullable": true
          },
          "limit": {
            "type": "integer",
            "format": "int64",
            "nullable": true
          },
          "updates": {
            "type": "array",
            "items": {
              "$ref": "#/components/schemas/Update"
            }
          }
        },
        "required": [
          "table",
          "updates"
        ]
      },
      "DashboardMetrics": {
        "type": "object",
        "properties": {
          "requestCount24h": {
            "type": "integer",
            "format": "int64"
          },
          "errorCount24h": {
            "type": "integer",
            "format": "int64"
          },
          "activeSessions": {
            "type": "integer",
            "format": "int64"
          },
          "p95ResponseMs": {
            "type": "integer",
            "format": "int64",
            "nullable": true
          },
          "requestBuckets": {
            "type": "array",
            "items": {
              "$ref": "#/components/schemas/DashboardRequestBucket"
            }
          }
        },
        "required": [
          "requestCount24h",
          "errorCount24h",
          "activeSessions",
          "requestBuckets"
        ]
      },
      "DashboardRequestBucket": {
        "type": "object",
        "properties": {
          "hour": {
            "type": "integer",
            "format": "int64"
          },
          "count": {
            "type": "integer",
            "format": "int64"
          }
        },
        "required": [
          "hour",
          "count"
        ]
      },
      "Decrement": {
        "type": "object"
      },
      "DeleteBody": {
        "type": "object",
        "properties": {
          "table": {
            "type": "string"
          },
          "where": {
            "$ref": "#/components/schemas/Where"
          },
          "limit": {
            "type": "integer",
            "format": "int64",
            "nullable": true
          }
        },
        "required": [
          "table",
          "where"
        ]
      },
      "DeleteOneBody": {
        "type": "object",
        "properties": {
          "table": {
            "type": "string"
          },
          "where": {
            "$ref": "#/components/schemas/Where"
          },
          "limit": {
            "type": "integer",
            "format": "int64",
            "nullable": true
          }
        },
        "required": [
          "table",
          "where"
        ]
      },
      "Email": {
        "type": "object",
        "properties": {
          "to": {
            "$ref": "#/components/schemas/EmailAddress"
          },
          "from": {
            "allOf": [
              {
                "$ref": "#/components/schemas/EmailAddress"
              }
            ],
            "nullable": true
          },
          "subject": {
            "type": "string"
          },
          "template": {
            "type": "string"
          },
          "variables": {
            "type": "object",
            "additionalProperties": true
          },
          "thread": {
            "type": "string",
            "nullable": true
          }
        },
        "required": [
          "to",
          "subject",
          "template",
          "variables"
        ]
      },
      "EmailAddress": {
        "type": "object",
        "properties": {
          "address": {
            "type": "string"
          },
          "name": {
            "type": "string",
            "nullable": true
          }
        },
        "required": [
          "address"
        ]
      },
      "EndsWith": {
        "type": "object",
        "properties": {
          "column": {
            "type": "string"
          },
          "value": {}
        },
        "required": [
          "column",
          "value"
        ]
      },
      "Eq": {
        "type": "object",
        "properties": {
          "column": {
            "type": "string"
          },
          "value": {}
        },
        "required": [
          "column",
          "value"
        ]
      },
      "GetBody": {
        "type": "object",
        "properties": {
          "table": {
            "type": "string"
          },
          "where": {
            "$ref": "#/components/schemas/Where"
          },
          "expand": {
            "type": "array",
            "items": {
              "type": "string"
            }
          }
        },
        "required": [
          "table",
          "where",
          "expand"
        ]
      },
      "Gt": {
        "type": "object",
        "properties": {
          "column": {
            "type": "string"
          },
          "value": {}
        },
        "required": [
          "column",
          "value"
        ]
      },
      "Gte": {
        "type": "object",
        "properties": {
          "column": {
            "type": "string"
          },
          "value": {}
        },
        "required": [
          "column",
          "value"
        ]
      },
      "In": {
        "type": "object",
        "properties": {
          "column": {
            "type": "string"
          },
          "values": {
            "type": "array",
            "items": {}
          }
        },
        "required": [
          "column",
          "values"
        ]
      },
      "Increment": {
        "type": "object"
      },
      "ListBody": {
        "type": "object",
        "properties": {
          "table": {
            "type": "string"
          },
          "where": {
            "allOf": [
              {
                "$ref": "#/components/schemas/Where"
              }
            ],
            "nullable": true
          },
          "expand": {
            "type": "array",
            "items": {
              "type": "string"
            }
          },
          "limit": {
            "type": "integer",
            "format": "int64",
            "nullable": true
          },
          "offset": {
            "type": "integer",
            "format": "int64",
            "nullable": true
          },
          "orderBy": {
            "type": "array",
            "items": {
              "$ref": "#/components/schemas/OrderByTerm"
            },
            "nullable": true
          },
          "groupBy": {
            "type": "string",
            "nullable": true
          }
        },
        "required": [
          "table",
          "expand"
        ]
      },
      "Literal": {
        "type": "object",
        "properties": {
          "value": {
            "nullable": true
          }
        }
      },
      "Lt": {
        "type": "object",
        "properties": {
          "column": {
            "type": "string"
          },
          "value": {}
        },
        "required": [
          "column",
          "value"
        ]
      },
      "Lte": {
        "type": "object",
        "properties": {
          "column": {
            "type": "string"
          },
          "value": {}
        },
        "required": [
          "column",
          "value"
        ]
      },
      "NotContains": {
        "type": "object",
        "properties": {
          "column": {
            "type": "string"
          },
          "value": {}
        },
        "required": [
          "column",
          "value"
        ]
      },
      "NotIn": {
        "type": "object",
        "properties": {
          "column": {
            "type": "string"
          },
          "values": {
            "type": "array",
            "items": {}
          }
        },
        "required": [
          "column",
          "values"
        ]
      },
      "NotNull": {
        "type": "object",
        "properties": {
          "column": {
            "type": "string"
          }
        },
        "required": [
          "column"
        ]
      },
      "Null": {
        "type": "object",
        "properties": {
          "column": {
            "type": "string"
          }
        },
        "required": [
          "column"
        ]
      },
      "OAuthBody": {
        "oneOf": [
          {
            "$ref": "#/components/schemas/OAuthIdTokenBody"
          },
          {
            "$ref": "#/components/schemas/OAuthCodeBody"
          }
        ]
      },
      "OAuthCallbackBody": {
        "type": "object",
        "properties": {
          "code": {
            "type": "string",
            "nullable": true
          },
          "state": {
            "type": "string",
            "nullable": true
          },
          "error": {
            "type": "string",
            "nullable": true
          },
          "errorDescription": {
            "type": "string",
            "nullable": true
          },
          "user": {
            "type": "string",
            "nullable": true
          }
        }
      },
      "OAuthCodeBody": {
        "type": "object",
        "properties": {
          "code": {
            "type": "string"
          },
          "codeVerifier": {
            "type": "string"
          },
          "redirectUri": {
            "type": "string"
          },
          "table": {
            "type": "string"
          },
          "provider": {
            "type": "string"
          },
          "type": {
            "type": "string"
          }
        },
        "required": [
          "code",
          "codeVerifier",
          "redirectUri",
          "table",
          "provider",
          "type"
        ]
      },
      "OAuthIdTokenBody": {
        "type": "object",
        "properties": {
          "idToken": {
            "type": "string"
          },
          "table": {
            "type": "string"
          },
          "provider": {
            "type": "string"
          },
          "type": {
            "type": "string"
          }
        },
        "required": [
          "idToken",
          "table",
          "provider",
          "type"
        ]
      },
      "ObjectUpdate": {
        "type": "object",
        "properties": {
          "object": {
            "type": "object",
            "additionalProperties": true
          }
        },
        "required": [
          "object"
        ]
      },
      "Or": {
        "type": "object",
        "properties": {
          "conditions": {
            "type": "array",
            "items": {
              "$ref": "#/components/schemas/Where"
            }
          }
        },
        "required": [
          "conditions"
        ]
      },
      "OrderByTerm": {
        "type": "object",
        "properties": {
          "column": {
            "type": "string"
          },
          "direction": {
            "$ref": "#/components/schemas/SortDirection"
          }
        },
        "required": [
          "column",
          "direction"
        ]
      },
      "PhotoCreateMeta": {
        "type": "object",
        "properties": {
          "table": {
            "type": "string"
          }
        },
        "required": [
          "table"
        ]
      },
      "Remove": {
        "type": "object",
        "properties": {
          "value": {
            "nullable": true
          }
        }
      },
      "RemoveAll": {
        "type": "object",
        "properties": {
          "values": {
            "type": "array",
            "items": {
              "nullable": true
            }
          }
        },
        "required": [
          "values"
        ]
      },
      "ResetPasswordAuthBody": {
        "oneOf": [
          {
            "$ref": "#/components/schemas/SendResetPasswordAuthBody"
          },
          {
            "$ref": "#/components/schemas/AdminSendResetPasswordAuthBody"
          }
        ]
      },
      "SendMagicLinkAuthBody": {
        "type": "object",
        "properties": {
          "email": {
            "type": "string"
          },
          "metadata": {
            "type": "object",
            "additionalProperties": true,
            "nullable": true
          },
          "table": {
            "type": "string"
          },
          "type": {
            "type": "string"
          }
        },
        "required": [
          "email",
          "table",
          "type"
        ]
      },
      "SendOtpAuthBody": {
        "type": "object",
        "properties": {
          "email": {
            "type": "string"
          },
          "metadata": {
            "type": "object",
            "additionalProperties": true,
            "nullable": true
          },
          "table": {
            "type": "string"
          },
          "type": {
            "type": "string"
          }
        },
        "required": [
          "email",
          "table",
          "type"
        ]
      },
      "SendResetPasswordAuthBody": {
        "type": "object",
        "properties": {
          "table": {
            "type": "string"
          },
          "type": {
            "type": "string"
          },
          "email": {
            "type": "string"
          }
        },
        "required": [
          "table",
          "type",
          "email"
        ]
      },
      "SignInAuthBody": {
        "type": "object",
        "properties": {
          "email": {
            "type": "string"
          },
          "password": {
            "type": "string"
          },
          "table": {
            "type": "string"
          },
          "type": {
            "type": "string"
          }
        },
        "required": [
          "email",
          "password",
          "table",
          "type"
        ]
      },
      "SignUpAuthBody": {
        "type": "object",
        "properties": {
          "email": {
            "type": "string"
          },
          "password": {
            "type": "string"
          },
          "object": {
            "type": "object",
            "additionalProperties": true,
            "nullable": true
          },
          "table": {
            "type": "string"
          },
          "type": {
            "type": "string"
          }
        },
        "required": [
          "email",
          "password",
          "table",
          "type"
        ]
      },
      "SortDirection": {
        "type": "string",
        "enum": [
          "asc",
          "desc"
        ]
      },
      "StartsWith": {
        "type": "object",
        "properties": {
          "column": {
            "type": "string"
          },
          "value": {}
        },
        "required": [
          "column",
          "value"
        ]
      },
      "StreamBody": {
        "type": "object",
        "properties": {
          "table": {
            "type": "string"
          },
          "where": {
            "$ref": "#/components/schemas/Where"
          },
          "expand": {
            "type": "array",
            "items": {
              "type": "string"
            }
          }
        },
        "required": [
          "table",
          "where",
          "expand"
        ]
      },
      "StreamCountBody": {
        "type": "object",
        "properties": {
          "table": {
            "type": "string"
          },
          "where": {
            "$ref": "#/components/schemas/Where"
          }
        },
        "required": [
          "table",
          "where"
        ]
      },
      "StreamListBody": {
        "type": "object",
        "properties": {
          "table": {
            "type": "string"
          },
          "where": {
            "allOf": [
              {
                "$ref": "#/components/schemas/Where"
              }
            ],
            "nullable": true
          },
          "limit": {
            "type": "integer",
            "format": "int64",
            "nullable": true
          },
          "offset": {
            "type": "integer",
            "format": "int64",
            "nullable": true
          },
          "orderBy": {
            "type": "array",
            "items": {
              "$ref": "#/components/schemas/OrderByTerm"
            },
            "nullable": true
          },
          "groupBy": {
            "type": "string",
            "nullable": true
          },
          "expand": {
            "type": "array",
            "items": {
              "type": "string"
            }
          }
        },
        "required": [
          "table",
          "expand"
        ]
      },
      "StringContent": {
        "type": "object",
        "properties": {
          "value": {
            "type": "string"
          }
        },
        "required": [
          "value"
        ]
      },
      "Update": {
        "oneOf": [
          {
            "$ref": "#/components/schemas/ColumnUpdate"
          },
          {
            "$ref": "#/components/schemas/ObjectUpdate"
          }
        ]
      },
      "UpdateBody": {
        "type": "object",
        "properties": {
          "table": {
            "type": "string"
          },
          "where": {
            "$ref": "#/components/schemas/Where"
          },
          "limit": {
            "type": "integer",
            "format": "int64",
            "nullable": true
          },
          "updates": {
            "type": "array",
            "items": {
              "$ref": "#/components/schemas/Update"
            }
          }
        },
        "required": [
          "table",
          "where",
          "updates"
        ]
      },
      "UpdateOneBody": {
        "type": "object",
        "properties": {
          "table": {
            "type": "string"
          },
          "where": {
            "$ref": "#/components/schemas/Where"
          },
          "limit": {
            "type": "integer",
            "format": "int64",
            "nullable": true
          },
          "updates": {
            "type": "array",
            "items": {
              "$ref": "#/components/schemas/Update"
            }
          }
        },
        "required": [
          "table",
          "where",
          "updates"
        ]
      },
      "UpdateValue": {
        "oneOf": [
          {
            "$ref": "#/components/schemas/Literal"
          },
          {
            "$ref": "#/components/schemas/Increment"
          },
          {
            "$ref": "#/components/schemas/Decrement"
          },
          {
            "$ref": "#/components/schemas/Add"
          },
          {
            "$ref": "#/components/schemas/Remove"
          },
          {
            "$ref": "#/components/schemas/AddAll"
          },
          {
            "$ref": "#/components/schemas/RemoveAll"
          }
        ]
      },
      "VerifyAuthBody": {
        "oneOf": [
          {
            "$ref": "#/components/schemas/VerifyOtpAuthBody"
          },
          {
            "$ref": "#/components/schemas/VerifyMagicLinkAuthBody"
          },
          {
            "$ref": "#/components/schemas/ConfirmResetPasswordAuthBody"
          },
          {
            "$ref": "#/components/schemas/ConfirmVerifyEmailAuthBody"
          }
        ]
      },
      "VerifyEmailAuthBody": {
        "type": "object",
        "properties": {
          "email": {
            "type": "string"
          },
          "table": {
            "type": "string"
          }
        },
        "required": [
          "email",
          "table"
        ]
      },
      "VerifyMagicLinkAuthBody": {
        "type": "object",
        "properties": {
          "secret": {
            "type": "string"
          },
          "type": {
            "type": "string"
          }
        },
        "required": [
          "secret",
          "type"
        ]
      },
      "VerifyOtpAuthBody": {
        "type": "object",
        "properties": {
          "email": {
            "type": "string"
          },
          "code": {
            "type": "string"
          },
          "type": {
            "type": "string"
          }
        },
        "required": [
          "email",
          "code",
          "type"
        ]
      },
      "Where": {
        "oneOf": [
          {
            "$ref": "#/components/schemas/Eq"
          },
          {
            "$ref": "#/components/schemas/Null"
          },
          {
            "$ref": "#/components/schemas/NotNull"
          },
          {
            "$ref": "#/components/schemas/Gt"
          },
          {
            "$ref": "#/components/schemas/Gte"
          },
          {
            "$ref": "#/components/schemas/Lt"
          },
          {
            "$ref": "#/components/schemas/Lte"
          },
          {
            "$ref": "#/components/schemas/In"
          },
          {
            "$ref": "#/components/schemas/NotIn"
          },
          {
            "$ref": "#/components/schemas/And"
          },
          {
            "$ref": "#/components/schemas/Or"
          },
          {
            "$ref": "#/components/schemas/Contains"
          },
          {
            "$ref": "#/components/schemas/StartsWith"
          },
          {
            "$ref": "#/components/schemas/EndsWith"
          },
          {
            "$ref": "#/components/schemas/NotContains"
          }
        ]
      }
    }
  }
}''';

const kSwaggerYaml = r'''openapi: 3.0.3
info:
  title: API
  version: 1.0.0
paths:
  '/admin/invites':
    post:
      operationId: admin_invite
      tags:
        - admin
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/AdminInviteBody'
      responses:
        '200':
          description: '`{email, table, expiresAt, isResend}`'
        '403':
          description: No Bearer token, or one that is not an admin for the resolved `AsAdmin` table
        '429':
          description: adminInvite rate limit exceeded, or this address was already invited within the last minute
  '/admin/invites/{email}':
    delete:
      operationId: admin_revokeInvite
      tags:
        - admin
      parameters:
        - name: email
          in: path
          required: true
          schema:
            type: string
      responses:
        '403':
          description: No Bearer token, or one that is not an admin for the resolved `AsAdmin` table
  '/admin/members':
    get:
      operationId: admin_members
      tags:
        - admin
      responses:
        '200':
          description: '`{admins: [...], invites: [{email, invitedAt, expiresAt, invitedByEmail}]}`'
        '403':
          description: No Bearer token, or one that is not an admin for the resolved `AsAdmin` table
  '/admin/members/{email}':
    delete:
      operationId: admin_removeMember
      tags:
        - admin
      parameters:
        - name: email
          in: path
          required: true
          schema:
            type: string
      responses:
        '200':
          description: The removed admin row, sanitized
        '403':
          description: No Bearer token, one that is not an admin for the resolved `AsAdmin` table, or an admin removing themselves
        '409':
          description: That is the table's last admin
  '/auth':
    delete:
      operationId: auth_logout
      tags:
        - auth
      responses:
        '200':
          description: No content
    post:
      operationId: auth_authenticate
      tags:
        - auth
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/AuthBody'
      responses:
        '200':
          description: Success
          content:
            application/json:
              schema:
                type: object
                additionalProperties: true
                nullable: true
  '/auth/admin':
    post:
      operationId: auth_adminAuthenticate
      tags:
        - auth
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/AdminAuthBody'
      responses:
        '200':
          description: Success
          content:
            application/json:
              schema:
                type: object
                additionalProperties: true
                nullable: true
  '/auth/admin/invite':
    get:
      operationId: auth_adminInviteStatus
      tags:
        - auth
      parameters:
        - name: token
          in: query
          required: true
          schema:
            type: string
      responses:
        '200':
          description: '`{live: true, table, authTypes}` when the token names an invite that can still be accepted, and `{live: false}` for every token that cannot -- expired, revoked, already accepted or unknown alike, deliberately indistinguishable. Never the invited email.'
        '429':
          description: oauthInviteStart rate limit exceeded
  '/auth/admin/invite/oauth/start/{provider}':
    get:
      operationId: auth_startAdminInviteOAuth
      tags:
        - auth
      parameters:
        - name: provider
          in: path
          required: true
          schema:
            type: string
        - name: token
          in: query
          required: true
          schema:
            type: string
        - name: redirect_to
          in: query
          required: false
          schema:
            type: string
            nullable: true
      responses:
        '302':
          description: Redirect to the provider's authorization endpoint. Carries `state` and `code_challenge` in the Location header.
        '400':
          description: '`redirect_to` is neither a relative path nor this app''s own origin'
        '401':
          description: The invite token names no live invite, or it has expired
        '404':
          description: No admin collection is configured for OAuth sign-in, or it has no such provider
        '429':
          description: oauthStart rate limit exceeded
  '/auth/admin/oauth/start/{provider}':
    get:
      operationId: auth_startAdminOAuth
      tags:
        - auth
      parameters:
        - name: provider
          in: path
          required: true
          schema:
            type: string
        - name: redirect_to
          in: query
          required: false
          schema:
            type: string
            nullable: true
      responses:
        '302':
          description: Redirect to the provider's authorization endpoint. Carries `state` and `code_challenge` in the Location header.
        '400':
          description: '`redirect_to` is neither a relative path nor this app''s own origin'
        '404':
          description: No admin collection is configured for OAuth sign-in, or it has no such provider
        '429':
          description: oauthStart rate limit exceeded
  '/auth/all':
    delete:
      operationId: auth_logoutAll
      tags:
        - auth
      responses:
        '200':
          description: No content
  '/auth/confirm':
    post:
      operationId: auth_confirm
      tags:
        - auth
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/VerifyAuthBody'
      responses:
        '200':
          description: Success
          content:
            application/json:
              schema:
                type: object
                additionalProperties: true
                nullable: true
  '/auth/oauth':
    post:
      operationId: auth_oauth
      tags:
        - auth
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/OAuthBody'
      responses:
        '200':
          description: Success
          content:
            application/json:
              schema:
                type: object
                additionalProperties: true
  '/auth/oauth/callback/{provider}':
    get:
      operationId: auth_oauthCallback
      tags:
        - auth
      parameters:
        - name: provider
          in: path
          required: true
          schema:
            type: string
        - name: code
          in: query
          required: false
          schema:
            type: string
            nullable: true
        - name: state
          in: query
          required: false
          schema:
            type: string
            nullable: true
        - name: error
          in: query
          required: false
          schema:
            type: string
            nullable: true
      responses:
        '302':
          description: Session minted; redirect to the `redirect_to` recorded at start
        '400':
          description: Provider returned `error`, or the callback carried no usable `code`/`state`
        '401':
          description: Unknown, replayed or expired `state`
        '429':
          description: oauthCallback rate limit exceeded
    post:
      operationId: auth_oauthCallbackFormPost
      tags:
        - auth
      parameters:
        - name: provider
          in: path
          required: true
          schema:
            type: string
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/OAuthCallbackBody'
      responses:
        '302':
          description: Session minted; redirect to the `redirect_to` recorded at start
        '400':
          description: Provider returned `error`, or the callback carried no usable `code`/`state`
        '401':
          description: Unknown, replayed or expired `state`
        '429':
          description: oauthCallback rate limit exceeded
  '/auth/oauth/providers':
    get:
      operationId: auth_oauthProviders
      tags:
        - auth
      parameters:
        - name: table
          in: query
          required: false
          schema:
            type: string
            nullable: true
      responses:
        '200':
          description: Success
          content:
            application/json:
              schema:
                type: array
                items:
                  type: object
                  additionalProperties: true
  '/auth/oauth/start/{provider}':
    get:
      operationId: auth_startOAuth
      tags:
        - auth
      parameters:
        - name: provider
          in: path
          required: true
          schema:
            type: string
        - name: table
          in: query
          required: true
          schema:
            type: string
        - name: redirect_to
          in: query
          required: false
          schema:
            type: string
            nullable: true
      responses:
        '302':
          description: Redirect to the provider's authorization endpoint. Carries `state` and `code_challenge` in the Location header.
        '400':
          description: '`redirect_to` is neither a relative path nor this app''s own origin'
        '404':
          description: No such provider on that table
        '429':
          description: oauthStart rate limit exceeded
  '/auth/refresh':
    post:
      operationId: auth_refreshToken
      tags:
        - auth
      responses:
        '200':
          description: Success
          content:
            application/json:
              schema:
                type: object
                additionalProperties: true
                nullable: true
  '/auth/reset-password':
    post:
      operationId: auth_sendResetPassword
      tags:
        - auth
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/ResetPasswordAuthBody'
      responses:
        '200':
          description: No content
  '/auth/sign-in':
    post:
      operationId: auth_signIn
      tags:
        - auth
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/SignInAuthBody'
      responses:
        '200':
          description: Success
          content:
            application/json:
              schema:
                type: object
                additionalProperties: true
  '/auth/sign-up':
    post:
      operationId: auth_signUp
      tags:
        - auth
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/SignUpAuthBody'
      responses:
        '200':
          description: Success
          content:
            application/json:
              schema:
                type: object
                additionalProperties: true
  '/auth/verify-email':
    post:
      operationId: auth_sendVerifyEmail
      tags:
        - auth
      requestBody:
        required: false
        content:
          application/json:
            schema:
              allOf:
                - $ref: '#/components/schemas/VerifyEmailAuthBody'
              nullable: true
      responses:
        '200':
          description: No content
  '/crons/list':
    get:
      operationId: cron_list
      tags:
        - cron
      responses:
        '200':
          description: Success
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/CronJobList'
  '/crons/run':
    post:
      operationId: cron_run
      tags:
        - cron
      parameters:
        - name: name
          in: query
          required: true
          schema:
            type: string
      responses:
        '200':
          description: No content
  '/dashboard/metrics':
    get:
      operationId: dashboard_metrics
      tags:
        - dashboard
      parameters:
        - name: since
          in: query
          required: false
          schema:
            type: integer
            format: int64
            nullable: true
        - name: exclude_admin
          in: query
          required: false
          schema:
            type: boolean
            nullable: true
      responses:
        '200':
          description: Success
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/DashboardMetrics'
  '/db':
    delete:
      operationId: db_delete
      tags:
        - db
      parameters:
        - name: body
          in: query
          required: true
          schema:
            $ref: '#/components/schemas/DeleteOneBody'
      responses:
        '200':
          description: No content
    get:
      operationId: db_get
      tags:
        - db
      parameters:
        - name: body
          in: query
          required: true
          schema:
            $ref: '#/components/schemas/GetBody'
      responses:
        '200':
          description: Success
          content:
            application/json:
              schema:
                type: object
                additionalProperties: true
    patch:
      operationId: db_update
      tags:
        - db
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/UpdateOneBody'
      responses:
        '200':
          description: Success
          content:
            application/json:
              schema:
                type: object
                additionalProperties: true
    post:
      operationId: db_create
      tags:
        - db
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/CreateBody'
      responses:
        '200':
          description: Success
          content:
            application/json:
              schema:
                type: object
                additionalProperties: true
  '/db/count':
    get:
      operationId: db_count
      tags:
        - db
      parameters:
        - name: body
          in: query
          required: true
          schema:
            $ref: '#/components/schemas/CountBody'
      responses:
        '200':
          description: Success
          content:
            application/json:
              schema:
                type: integer
                format: int64
  '/db/custom/{operation}':
    patch:
      operationId: db_custom
      tags:
        - db
      parameters:
        - name: operation
          in: path
          required: true
          schema:
            type: string
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/CustomOneBody'
      responses:
        '200':
          description: Success
          content:
            application/json:
              schema:
                type: object
                additionalProperties: true
  '/db/custom/{operation}/many':
    patch:
      operationId: db_customMany
      tags:
        - db
      parameters:
        - name: operation
          in: path
          required: true
          schema:
            type: string
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/CustomBody'
      responses:
        '200':
          description: Success
          content:
            application/json:
              schema:
                type: array
                items:
                  type: object
                  additionalProperties: true
  '/db/list':
    get:
      operationId: db_list
      tags:
        - db
      parameters:
        - name: body
          in: query
          required: true
          schema:
            $ref: '#/components/schemas/ListBody'
      responses:
        '200':
          description: Success
          content:
            application/json:
              schema:
                type: object
                additionalProperties: true
  '/db/many':
    delete:
      operationId: db_deleteMany
      tags:
        - db
      parameters:
        - name: body
          in: query
          required: true
          schema:
            $ref: '#/components/schemas/DeleteBody'
      responses:
        '200':
          description: No content
    patch:
      operationId: db_updateMany
      tags:
        - db
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/UpdateBody'
      responses:
        '200':
          description: Success
          content:
            application/json:
              schema:
                type: array
                items:
                  type: object
                  additionalProperties: true
    post:
      operationId: db_createMany
      tags:
        - db
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/CreateManyBody'
      responses:
        '200':
          description: Success
          content:
            application/json:
              schema:
                type: array
                items:
                  type: object
                  additionalProperties: true
  '/db/stream':
    get:
      operationId: db_streamOne
      tags:
        - db
      parameters:
        - name: body
          in: query
          required: true
          schema:
            $ref: '#/components/schemas/StreamBody'
      responses:
        '200':
          description: Success
          content:
            application/json:
              schema:
                type: object
                additionalProperties: true
  '/db/stream/count':
    get:
      operationId: db_streamCount
      tags:
        - db
      parameters:
        - name: body
          in: query
          required: true
          schema:
            $ref: '#/components/schemas/StreamCountBody'
      responses:
        '200':
          description: Success
          content:
            application/json:
              schema:
                type: integer
                format: int64
  '/db/stream/list':
    get:
      operationId: db_streamList
      tags:
        - db
      parameters:
        - name: body
          in: query
          required: true
          schema:
            $ref: '#/components/schemas/StreamListBody'
      responses:
        '200':
          description: Success
          content:
            application/json:
              schema:
                type: array
                items:
                  type: object
                  additionalProperties: true
  '/email':
    post:
      operationId: email_send
      tags:
        - email
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/Email'
      responses:
        '200':
          description: No content
  '/health':
    get:
      operationId: root_health
      tags:
        - root
      responses:
        '200':
          description: No content
  '/img':
    post:
      operationId: photos_create
      tags:
        - photos
      parameters:
        - name: meta
          in: query
          required: true
          schema:
            $ref: '#/components/schemas/PhotoCreateMeta'
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: array
              items:
                type: integer
                format: int64
      responses:
        '200':
          description: Success
          content:
            application/json:
              schema:
                type: object
                additionalProperties: true
  '/img/{id}':
    delete:
      operationId: photos_delete
      tags:
        - photos
      parameters:
        - name: id
          in: path
          required: true
          schema:
            type: string
      responses:
        '200':
          description: No content
    get:
      operationId: photos_view
      tags:
        - photos
      parameters:
        - name: id
          in: path
          required: true
          schema:
            type: string
      responses:
        '200':
          description: Success
          content:
            application/json:
              schema:
                type: array
                items:
                  type: integer
                  format: int64
    patch:
      operationId: photos_update
      tags:
        - photos
      parameters:
        - name: id
          in: path
          required: true
          schema:
            type: string
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: array
              items:
                type: integer
                format: int64
      responses:
        '200':
          description: No content
  '/swagger.json':
    get:
      operationId: root_swaggerJson
      tags:
        - root
      responses:
        '200':
          description: Success
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/StringContent'
  '/swagger.yaml':
    get:
      operationId: root_swaggerYaml
      tags:
        - root
      responses:
        '200':
          description: Success
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/StringContent'
components:
  schemas:
    Add:
      type: object
      properties:
        value:
          nullable: true
    AddAll:
      type: object
      properties:
        values:
          type: array
          items:
            nullable: true
      required:
        - values
    AdminAuthBody:
      type: object
      properties:
        type:
          type: string
      required:
        - type
    AdminInviteBody:
      type: object
      properties:
        email:
          type: string
      required:
        - email
    AdminSendResetPasswordAuthBody:
      type: object
      properties:
        type:
          type: string
        email:
          type: string
      required:
        - type
        - email
    And:
      type: object
      properties:
        conditions:
          type: array
          items:
            $ref: '#/components/schemas/Where'
      required:
        - conditions
    AuthBody:
      oneOf:
        - $ref: '#/components/schemas/SendOtpAuthBody'
        - $ref: '#/components/schemas/SendMagicLinkAuthBody'
        - $ref: '#/components/schemas/SignInAuthBody'
        - $ref: '#/components/schemas/SignUpAuthBody'
    ColumnUpdate:
      type: object
      properties:
        column:
          type: string
        value:
          $ref: '#/components/schemas/UpdateValue'
      required:
        - column
        - value
    ConfirmResetPasswordAuthBody:
      type: object
      properties:
        token:
          type: string
        newPassword:
          type: string
        type:
          type: string
      required:
        - token
        - newPassword
        - type
    ConfirmVerifyEmailAuthBody:
      type: object
      properties:
        token:
          type: string
        type:
          type: string
      required:
        - token
        - type
    Contains:
      type: object
      properties:
        column:
          type: string
        value: {}
      required:
        - column
        - value
    CountBody:
      type: object
      properties:
        table:
          type: string
        where:
          allOf:
            - $ref: '#/components/schemas/Where'
          nullable: true
      required:
        - table
    CreateBody:
      type: object
      properties:
        table:
          type: string
        object:
          type: object
          additionalProperties: true
      required:
        - table
        - object
    CreateManyBody:
      type: object
      properties:
        table:
          type: string
        objects:
          type: array
          items:
            type: object
            additionalProperties: true
      required:
        - table
        - objects
    CronJobList:
      type: object
      properties:
        names:
          type: array
          items:
            type: string
      required:
        - names
    CustomBody:
      type: object
      properties:
        table:
          type: string
        where:
          allOf:
            - $ref: '#/components/schemas/Where'
          nullable: true
        limit:
          type: integer
          format: int64
          nullable: true
        updates:
          type: array
          items:
            $ref: '#/components/schemas/Update'
      required:
        - table
        - updates
    CustomOneBody:
      type: object
      properties:
        table:
          type: string
        where:
          allOf:
            - $ref: '#/components/schemas/Where'
          nullable: true
        limit:
          type: integer
          format: int64
          nullable: true
        updates:
          type: array
          items:
            $ref: '#/components/schemas/Update'
      required:
        - table
        - updates
    DashboardMetrics:
      type: object
      properties:
        requestCount24h:
          type: integer
          format: int64
        errorCount24h:
          type: integer
          format: int64
        activeSessions:
          type: integer
          format: int64
        p95ResponseMs:
          type: integer
          format: int64
          nullable: true
        requestBuckets:
          type: array
          items:
            $ref: '#/components/schemas/DashboardRequestBucket'
      required:
        - requestCount24h
        - errorCount24h
        - activeSessions
        - requestBuckets
    DashboardRequestBucket:
      type: object
      properties:
        hour:
          type: integer
          format: int64
        count:
          type: integer
          format: int64
      required:
        - hour
        - count
    Decrement:
      type: object
    DeleteBody:
      type: object
      properties:
        table:
          type: string
        where:
          $ref: '#/components/schemas/Where'
        limit:
          type: integer
          format: int64
          nullable: true
      required:
        - table
        - where
    DeleteOneBody:
      type: object
      properties:
        table:
          type: string
        where:
          $ref: '#/components/schemas/Where'
        limit:
          type: integer
          format: int64
          nullable: true
      required:
        - table
        - where
    Email:
      type: object
      properties:
        to:
          $ref: '#/components/schemas/EmailAddress'
        from:
          allOf:
            - $ref: '#/components/schemas/EmailAddress'
          nullable: true
        subject:
          type: string
        template:
          type: string
        variables:
          type: object
          additionalProperties: true
        thread:
          type: string
          nullable: true
      required:
        - to
        - subject
        - template
        - variables
    EmailAddress:
      type: object
      properties:
        address:
          type: string
        name:
          type: string
          nullable: true
      required:
        - address
    EndsWith:
      type: object
      properties:
        column:
          type: string
        value: {}
      required:
        - column
        - value
    Eq:
      type: object
      properties:
        column:
          type: string
        value: {}
      required:
        - column
        - value
    GetBody:
      type: object
      properties:
        table:
          type: string
        where:
          $ref: '#/components/schemas/Where'
        expand:
          type: array
          items:
            type: string
      required:
        - table
        - where
        - expand
    Gt:
      type: object
      properties:
        column:
          type: string
        value: {}
      required:
        - column
        - value
    Gte:
      type: object
      properties:
        column:
          type: string
        value: {}
      required:
        - column
        - value
    In:
      type: object
      properties:
        column:
          type: string
        values:
          type: array
          items: {}
      required:
        - column
        - values
    Increment:
      type: object
    ListBody:
      type: object
      properties:
        table:
          type: string
        where:
          allOf:
            - $ref: '#/components/schemas/Where'
          nullable: true
        expand:
          type: array
          items:
            type: string
        limit:
          type: integer
          format: int64
          nullable: true
        offset:
          type: integer
          format: int64
          nullable: true
        orderBy:
          type: array
          items:
            $ref: '#/components/schemas/OrderByTerm'
          nullable: true
        groupBy:
          type: string
          nullable: true
      required:
        - table
        - expand
    Literal:
      type: object
      properties:
        value:
          nullable: true
    Lt:
      type: object
      properties:
        column:
          type: string
        value: {}
      required:
        - column
        - value
    Lte:
      type: object
      properties:
        column:
          type: string
        value: {}
      required:
        - column
        - value
    NotContains:
      type: object
      properties:
        column:
          type: string
        value: {}
      required:
        - column
        - value
    NotIn:
      type: object
      properties:
        column:
          type: string
        values:
          type: array
          items: {}
      required:
        - column
        - values
    NotNull:
      type: object
      properties:
        column:
          type: string
      required:
        - column
    'Null':
      type: object
      properties:
        column:
          type: string
      required:
        - column
    OAuthBody:
      oneOf:
        - $ref: '#/components/schemas/OAuthIdTokenBody'
        - $ref: '#/components/schemas/OAuthCodeBody'
    OAuthCallbackBody:
      type: object
      properties:
        code:
          type: string
          nullable: true
        state:
          type: string
          nullable: true
        error:
          type: string
          nullable: true
        errorDescription:
          type: string
          nullable: true
        user:
          type: string
          nullable: true
    OAuthCodeBody:
      type: object
      properties:
        code:
          type: string
        codeVerifier:
          type: string
        redirectUri:
          type: string
        table:
          type: string
        provider:
          type: string
        type:
          type: string
      required:
        - code
        - codeVerifier
        - redirectUri
        - table
        - provider
        - type
    OAuthIdTokenBody:
      type: object
      properties:
        idToken:
          type: string
        table:
          type: string
        provider:
          type: string
        type:
          type: string
      required:
        - idToken
        - table
        - provider
        - type
    ObjectUpdate:
      type: object
      properties:
        object:
          type: object
          additionalProperties: true
      required:
        - object
    Or:
      type: object
      properties:
        conditions:
          type: array
          items:
            $ref: '#/components/schemas/Where'
      required:
        - conditions
    OrderByTerm:
      type: object
      properties:
        column:
          type: string
        direction:
          $ref: '#/components/schemas/SortDirection'
      required:
        - column
        - direction
    PhotoCreateMeta:
      type: object
      properties:
        table:
          type: string
      required:
        - table
    Remove:
      type: object
      properties:
        value:
          nullable: true
    RemoveAll:
      type: object
      properties:
        values:
          type: array
          items:
            nullable: true
      required:
        - values
    ResetPasswordAuthBody:
      oneOf:
        - $ref: '#/components/schemas/SendResetPasswordAuthBody'
        - $ref: '#/components/schemas/AdminSendResetPasswordAuthBody'
    SendMagicLinkAuthBody:
      type: object
      properties:
        email:
          type: string
        metadata:
          type: object
          additionalProperties: true
          nullable: true
        table:
          type: string
        type:
          type: string
      required:
        - email
        - table
        - type
    SendOtpAuthBody:
      type: object
      properties:
        email:
          type: string
        metadata:
          type: object
          additionalProperties: true
          nullable: true
        table:
          type: string
        type:
          type: string
      required:
        - email
        - table
        - type
    SendResetPasswordAuthBody:
      type: object
      properties:
        table:
          type: string
        type:
          type: string
        email:
          type: string
      required:
        - table
        - type
        - email
    SignInAuthBody:
      type: object
      properties:
        email:
          type: string
        password:
          type: string
        table:
          type: string
        type:
          type: string
      required:
        - email
        - password
        - table
        - type
    SignUpAuthBody:
      type: object
      properties:
        email:
          type: string
        password:
          type: string
        object:
          type: object
          additionalProperties: true
          nullable: true
        table:
          type: string
        type:
          type: string
      required:
        - email
        - password
        - table
        - type
    SortDirection:
      type: string
      enum:
        - asc
        - desc
    StartsWith:
      type: object
      properties:
        column:
          type: string
        value: {}
      required:
        - column
        - value
    StreamBody:
      type: object
      properties:
        table:
          type: string
        where:
          $ref: '#/components/schemas/Where'
        expand:
          type: array
          items:
            type: string
      required:
        - table
        - where
        - expand
    StreamCountBody:
      type: object
      properties:
        table:
          type: string
        where:
          $ref: '#/components/schemas/Where'
      required:
        - table
        - where
    StreamListBody:
      type: object
      properties:
        table:
          type: string
        where:
          allOf:
            - $ref: '#/components/schemas/Where'
          nullable: true
        limit:
          type: integer
          format: int64
          nullable: true
        offset:
          type: integer
          format: int64
          nullable: true
        orderBy:
          type: array
          items:
            $ref: '#/components/schemas/OrderByTerm'
          nullable: true
        groupBy:
          type: string
          nullable: true
        expand:
          type: array
          items:
            type: string
      required:
        - table
        - expand
    StringContent:
      type: object
      properties:
        value:
          type: string
      required:
        - value
    Update:
      oneOf:
        - $ref: '#/components/schemas/ColumnUpdate'
        - $ref: '#/components/schemas/ObjectUpdate'
    UpdateBody:
      type: object
      properties:
        table:
          type: string
        where:
          $ref: '#/components/schemas/Where'
        limit:
          type: integer
          format: int64
          nullable: true
        updates:
          type: array
          items:
            $ref: '#/components/schemas/Update'
      required:
        - table
        - where
        - updates
    UpdateOneBody:
      type: object
      properties:
        table:
          type: string
        where:
          $ref: '#/components/schemas/Where'
        limit:
          type: integer
          format: int64
          nullable: true
        updates:
          type: array
          items:
            $ref: '#/components/schemas/Update'
      required:
        - table
        - where
        - updates
    UpdateValue:
      oneOf:
        - $ref: '#/components/schemas/Literal'
        - $ref: '#/components/schemas/Increment'
        - $ref: '#/components/schemas/Decrement'
        - $ref: '#/components/schemas/Add'
        - $ref: '#/components/schemas/Remove'
        - $ref: '#/components/schemas/AddAll'
        - $ref: '#/components/schemas/RemoveAll'
    VerifyAuthBody:
      oneOf:
        - $ref: '#/components/schemas/VerifyOtpAuthBody'
        - $ref: '#/components/schemas/VerifyMagicLinkAuthBody'
        - $ref: '#/components/schemas/ConfirmResetPasswordAuthBody'
        - $ref: '#/components/schemas/ConfirmVerifyEmailAuthBody'
    VerifyEmailAuthBody:
      type: object
      properties:
        email:
          type: string
        table:
          type: string
      required:
        - email
        - table
    VerifyMagicLinkAuthBody:
      type: object
      properties:
        secret:
          type: string
        type:
          type: string
      required:
        - secret
        - type
    VerifyOtpAuthBody:
      type: object
      properties:
        email:
          type: string
        code:
          type: string
        type:
          type: string
      required:
        - email
        - code
        - type
    Where:
      oneOf:
        - $ref: '#/components/schemas/Eq'
        - $ref: '#/components/schemas/Null'
        - $ref: '#/components/schemas/NotNull'
        - $ref: '#/components/schemas/Gt'
        - $ref: '#/components/schemas/Gte'
        - $ref: '#/components/schemas/Lt'
        - $ref: '#/components/schemas/Lte'
        - $ref: '#/components/schemas/In'
        - $ref: '#/components/schemas/NotIn'
        - $ref: '#/components/schemas/And'
        - $ref: '#/components/schemas/Or'
        - $ref: '#/components/schemas/Contains'
        - $ref: '#/components/schemas/StartsWith'
        - $ref: '#/components/schemas/EndsWith'
        - $ref: '#/components/schemas/NotContains'
''';

