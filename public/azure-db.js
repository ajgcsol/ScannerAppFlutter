/**
 * Firestore-compatibility layer over the Azure Functions data API.
 *
 * admin-portal.js was written against the firebase.firestore() compat API and
 * makes ~76 direct calls to it. Rather than rewrite those call sites, this file
 * re-implements the subset actually used — doc/get/set/add/update/delete,
 * where/orderBy/limit, batches, and storage refs — and installs itself as the
 * global `firebase`, so admin-portal.js runs unmodified.
 *
 * Load order matters: this must come before admin-portal.js, and the real
 * Firebase CDN bundles must NOT be loaded alongside it.
 */
(function () {
  "use strict";

  var CONFIG = (window.INSESSION_CONFIG = window.INSESSION_CONFIG || {});
  var API_BASE = (CONFIG.apiBase || "").replace(/\/$/, "");
  var CLIENT_ID = CONFIG.clientId || null;

  // ---------------------------------------------------------------- auth ----

  // The portal signs in with MSAL; every data call carries that token. Falls
  // back to the ID token when the app registration exposes no API scope.
  function getToken() {
    if (typeof msalInstance === "undefined" || !msalInstance) {
      return Promise.resolve(null);
    }
    var accounts = msalInstance.getAllAccounts();
    if (!accounts || accounts.length === 0) return Promise.resolve(null);

    var request = { account: accounts[0] };
    var apiScopes = CLIENT_ID ? ["api://" + CLIENT_ID + "/access_as_user"] : null;

    var attempt = apiScopes
      ? msalInstance
          .acquireTokenSilent(Object.assign({ scopes: apiScopes }, request))
          .then(function (r) {
            return r.accessToken || r.idToken;
          })
          .catch(function () {
            return null;
          })
      : Promise.resolve(null);

    return attempt.then(function (token) {
      if (token) return token;
      return msalInstance
        .acquireTokenSilent(Object.assign({ scopes: ["openid", "profile"] }, request))
        .then(function (r) {
          return r.idToken || r.accessToken;
        })
        .catch(function () {
          return null;
        });
    });
  }

  function apiFetch(path, options) {
    options = options || {};
    return getToken().then(function (token) {
      var headers = { "Content-Type": "application/json" };
      if (token) headers.Authorization = "Bearer " + token;
      if (CONFIG.apiKey) headers["x-api-key"] = CONFIG.apiKey;

      return fetch(API_BASE + path, {
        method: options.method || "GET",
        headers: headers,
        body: options.body ? JSON.stringify(options.body) : undefined,
      }).then(function (res) {
        if (res.status === 404 && options.tolerate404) return null;
        if (!res.ok) {
          return res.text().then(function (text) {
            throw new Error("API " + res.status + " on " + path + ": " + text);
          });
        }
        if (res.status === 204) return null;
        return res.json();
      });
    });
  }

  // ------------------------------------------------------------ snapshots ----

  function docSnapshot(data, id, ref) {
    return {
      id: id,
      ref: ref,
      exists: data !== null && data !== undefined,
      data: function () {
        return data;
      },
    };
  }

  function querySnapshot(rows, collectionRef) {
    var docs = rows.map(function (row) {
      return docSnapshot(row, row.id, collectionRef.doc(row.id));
    });
    return {
      docs: docs,
      size: docs.length,
      empty: docs.length === 0,
      forEach: function (fn) {
        docs.forEach(fn);
      },
    };
  }

  // ---------------------------------------------------------------- refs ----

  var OPS = {
    "==": "eq",
    "!=": "ne",
    ">": "gt",
    ">=": "gte",
    "<": "lt",
    "<=": "lte",
  };

  function serializeValue(value) {
    if (value instanceof Date) return value.toISOString();
    return String(value);
  }

  function Query(path, filters, orders, limitCount) {
    this._path = path;
    this._filters = filters || [];
    this._orders = orders || [];
    this._limit = limitCount || null;
  }

  Query.prototype.where = function (field, op, value) {
    if (!OPS[op]) throw new Error("Unsupported operator: " + op);
    return new Query(
      this._path,
      this._filters.concat([field + ":" + OPS[op] + ":" + serializeValue(value)]),
      this._orders,
      this._limit
    );
  };

  Query.prototype.orderBy = function (field, direction) {
    return new Query(
      this._path,
      this._filters,
      this._orders.concat([field + (direction ? " " + direction : "")]),
      this._limit
    );
  };

  Query.prototype.limit = function (count) {
    return new Query(this._path, this._filters, this._orders, count);
  };

  Query.prototype.doc = function (id) {
    return new DocRef(this._path + "/" + id);
  };

  Query.prototype.get = function () {
    var params = [];
    this._filters.forEach(function (f) {
      params.push("where=" + encodeURIComponent(f));
    });
    if (this._orders.length) {
      params.push("orderBy=" + encodeURIComponent(this._orders.join(",")));
    }
    if (this._limit) params.push("limit=" + this._limit);

    var qs = params.length ? "?" + params.join("&") : "";
    var self = this;
    return apiFetch("/data/" + this._path + qs).then(function (rows) {
      return querySnapshot(rows || [], new CollectionRef(self._path));
    });
  };

  function CollectionRef(path) {
    Query.call(this, path, [], [], null);
    this.path = path;
  }
  CollectionRef.prototype = Object.create(Query.prototype);
  CollectionRef.prototype.constructor = CollectionRef;

  CollectionRef.prototype.doc = function (id) {
    return new DocRef(this.path + "/" + id);
  };

  CollectionRef.prototype.add = function (data) {
    var self = this;
    return apiFetch("/data/" + this.path, { method: "POST", body: data }).then(
      function (created) {
        return self.doc(created.id);
      }
    );
  };

  function DocRef(path) {
    this.path = path;
    var segments = path.split("/");
    this.id = segments[segments.length - 1];
  }

  DocRef.prototype.collection = function (name) {
    return new CollectionRef(this.path + "/" + name);
  };

  DocRef.prototype.get = function () {
    var self = this;
    return apiFetch("/data/" + this.path, { tolerate404: true }).then(function (data) {
      return docSnapshot(data, self.id, self);
    });
  };

  DocRef.prototype.set = function (data, options) {
    var merge = options && options.merge ? "?merge=true" : "";
    return apiFetch("/data/" + this.path + merge, { method: "PUT", body: data });
  };

  DocRef.prototype.update = function (data) {
    return apiFetch("/data/" + this.path, { method: "PATCH", body: data });
  };

  DocRef.prototype.delete = function () {
    return apiFetch("/data/" + this.path, { method: "DELETE" });
  };

  // -------------------------------------------------------------- batches ----

  function WriteBatch() {
    this._ops = [];
  }

  WriteBatch.prototype.set = function (ref, data, options) {
    this._ops.push({
      type: options && options.merge ? "merge" : "set",
      path: ref.path,
      data: data,
    });
    return this;
  };

  WriteBatch.prototype.update = function (ref, data) {
    this._ops.push({ type: "update", path: ref.path, data: data });
    return this;
  };

  WriteBatch.prototype.delete = function (ref) {
    this._ops.push({ type: "delete", path: ref.path });
    return this;
  };

  WriteBatch.prototype.commit = function () {
    if (this._ops.length === 0) return Promise.resolve({ success: true, applied: 0 });
    var ops = this._ops;
    this._ops = [];
    return apiFetch("/batch", { method: "POST", body: { operations: ops } }).then(
      function (result) {
        if (result && result.success === false) {
          var failed = (result.results || []).filter(function (r) {
            return !r.success;
          });
          throw new Error(
            "Batch partially failed (" +
              failed.length +
              " of " +
              result.total +
              "): " +
              failed
                .map(function (f) {
                  return f.path + " - " + f.error;
                })
                .join("; ")
          );
        }
        return result;
      }
    );
  };

  // -------------------------------------------------------------- storage ----

  function StorageRef(path) {
    this.path = path;
  }

  StorageRef.prototype.put = function (file) {
    var self = this;
    // Uploads go through the API so the storage account needs no public access
    // and no SAS is ever handed to the browser.
    return getToken().then(function (token) {
      var headers = {
        "Content-Type": file.type || "application/octet-stream",
        "x-photo-path": self.path,
      };
      if (token) headers.Authorization = "Bearer " + token;
      if (CONFIG.apiKey) headers["x-api-key"] = CONFIG.apiKey;

      return fetch(API_BASE + "/uploadPhoto", {
        method: "POST",
        headers: headers,
        body: file,
      })
        .then(function (res) {
          if (!res.ok) {
            return res.text().then(function (text) {
              throw new Error("Upload failed " + res.status + ": " + text);
            });
          }
          return res.json();
        })
        .then(function (result) {
          return {
            ref: self,
            metadata: { fullPath: self.path },
            _url: result.url,
          };
        });
    });
  };

  StorageRef.prototype.getDownloadURL = function () {
    return apiFetch("/photoUrl?path=" + encodeURIComponent(this.path)).then(
      function (result) {
        return result.url;
      }
    );
  };

  // -------------------------------------------------- firebase namespace ----

  var firestoreApi = function () {
    return {
      collection: function (name) {
        return new CollectionRef(name);
      },
      batch: function () {
        return new WriteBatch();
      },
      // Present so callers that reach for it don't fail; there is no offline
      // cache behind this shim.
      enablePersistence: function () {
        return Promise.resolve();
      },
    };
  };

  firestoreApi.FieldValue = {
    // Resolved on the client. Cosmos has no server-side sentinel, and every
    // consumer of these fields treats them as ISO-8601 strings.
    serverTimestamp: function () {
      return new Date().toISOString();
    },
    delete: function () {
      return null;
    },
  };

  firestoreApi.Timestamp = {
    now: function () {
      return new Date().toISOString();
    },
    fromDate: function (date) {
      return date.toISOString();
    },
  };

  window.firebase = {
    initializeApp: function () {
      if (!API_BASE) {
        console.error(
          "[azure-db] window.INSESSION_CONFIG.apiBase is not set; data calls will fail."
        );
      }
      return { name: "azure-shim" };
    },
    firestore: firestoreApi,
    storage: function () {
      return {
        ref: function (path) {
          return new StorageRef(path);
        },
      };
    },
  };

  window.INSESSION_AZURE_DB = {
    CollectionRef: CollectionRef,
    DocRef: DocRef,
    WriteBatch: WriteBatch,
    apiFetch: apiFetch,
    getToken: getToken,
  };
})();
