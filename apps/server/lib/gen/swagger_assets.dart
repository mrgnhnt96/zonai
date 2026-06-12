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
                  "type": "string"
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
                  "type": "string"
                }
              }
            }
          }
        }
      }
    },
    "/img/{id}": {
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
      },
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
    "/db": {
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
    "/db/many": {
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
      }
    },
    "/auth": {
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
      },
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
    }
  },
  "components": {
    "schemas": {
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
          }
        },
        "required": [
          "table",
          "expand"
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
      "SortDirection": {
        "type": "string",
        "enum": [
          "asc",
          "desc"
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
      "Literal": {
        "type": "object",
        "properties": {
          "value": {
            "nullable": true
          }
        }
      },
      "Increment": {
        "type": "object"
      },
      "Decrement": {
        "type": "object"
      },
      "Add": {
        "type": "object",
        "properties": {
          "value": {
            "nullable": true
          }
        }
      },
      "Remove": {
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
      }
    }
  }
}''';

const kSwaggerYaml = r'''openapi: 3.0.3
info:
  title: API
  version: 1.0.0
paths:
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
                type: string
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
                type: string
  '/img/{id}':
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
  '/db':
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
  '/db/many':
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
  '/auth':
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
    delete:
      operationId: auth_logout
      tags:
        - auth
      responses:
        '200':
          description: No content
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
  '/auth/all':
    delete:
      operationId: auth_logoutAll
      tags:
        - auth
      responses:
        '200':
          description: No content
components:
  schemas:
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
    PhotoCreateMeta:
      type: object
      properties:
        table:
          type: string
      required:
        - table
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
    Eq:
      type: object
      properties:
        column:
          type: string
        value: {}
      required:
        - column
        - value
    'Null':
      type: object
      properties:
        column:
          type: string
      required:
        - column
    NotNull:
      type: object
      properties:
        column:
          type: string
      required:
        - column
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
    And:
      type: object
      properties:
        conditions:
          type: array
          items:
            $ref: '#/components/schemas/Where'
      required:
        - conditions
    Or:
      type: object
      properties:
        conditions:
          type: array
          items:
            $ref: '#/components/schemas/Where'
      required:
        - conditions
    Contains:
      type: object
      properties:
        column:
          type: string
        value: {}
      required:
        - column
        - value
    StartsWith:
      type: object
      properties:
        column:
          type: string
        value: {}
      required:
        - column
        - value
    EndsWith:
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
      required:
        - table
        - expand
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
    SortDirection:
      type: string
      enum:
        - asc
        - desc
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
        expand:
          type: array
          items:
            type: string
      required:
        - table
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
    Update:
      oneOf:
        - $ref: '#/components/schemas/ColumnUpdate'
        - $ref: '#/components/schemas/ObjectUpdate'
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
    UpdateValue:
      oneOf:
        - $ref: '#/components/schemas/Literal'
        - $ref: '#/components/schemas/Increment'
        - $ref: '#/components/schemas/Decrement'
        - $ref: '#/components/schemas/Add'
        - $ref: '#/components/schemas/Remove'
        - $ref: '#/components/schemas/AddAll'
        - $ref: '#/components/schemas/RemoveAll'
    Literal:
      type: object
      properties:
        value:
          nullable: true
    Increment:
      type: object
    Decrement:
      type: object
    Add:
      type: object
      properties:
        value:
          nullable: true
    Remove:
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
    RemoveAll:
      type: object
      properties:
        values:
          type: array
          items:
            nullable: true
      required:
        - values
    ObjectUpdate:
      type: object
      properties:
        object:
          type: object
          additionalProperties: true
      required:
        - object
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
    AuthBody:
      oneOf:
        - $ref: '#/components/schemas/SendOtpAuthBody'
        - $ref: '#/components/schemas/SendMagicLinkAuthBody'
        - $ref: '#/components/schemas/SignInAuthBody'
        - $ref: '#/components/schemas/SignUpAuthBody'
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
    ResetPasswordAuthBody:
      oneOf:
        - $ref: '#/components/schemas/SendResetPasswordAuthBody'
        - $ref: '#/components/schemas/AdminSendResetPasswordAuthBody'
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
    VerifyAuthBody:
      oneOf:
        - $ref: '#/components/schemas/VerifyOtpAuthBody'
        - $ref: '#/components/schemas/VerifyMagicLinkAuthBody'
        - $ref: '#/components/schemas/ConfirmResetPasswordAuthBody'
        - $ref: '#/components/schemas/ConfirmVerifyEmailAuthBody'
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
    AdminAuthBody:
      type: object
      properties:
        type:
          type: string
      required:
        - type
''';

