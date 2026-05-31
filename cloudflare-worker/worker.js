// Cloudflare Worker for asiimov-img R2 Bucket
// Handles secure uploads and deletions using Firebase Auth JWTs.

export default {
  async fetch(request, env) {
    const corsHeaders = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, HEAD, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    };

    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders });
    }

    // Must be PUT (upload) or DELETE
    if (request.method !== 'PUT' && request.method !== 'DELETE') {
      return new Response('Method Not Allowed', { status: 405, headers: corsHeaders });
    }

    // 1. JWT Verification
    const authHeader = request.headers.get('Authorization');
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return new Response('Unauthorized - Missing Token', { status: 401, headers: corsHeaders });
    }
    const token = authHeader.split(' ')[1];

    let decodedUid;
    try {
      // Hardcoded Firebase Project ID to avoid environment variable issues
      decodedUid = await verifyFirebaseJWT(token, 'asiimov-b3792');
    } catch (error) {
      return new Response('Unauthorized - Invalid Token: ' + error.message, { status: 401, headers: corsHeaders });
    }

    // 2. Validate Path and Ownership
    const url = new URL(request.url);
    const path = url.pathname.slice(1); // e.g., pfp/user123.jpg or chat_files/user123/uuid_file.pdf

    let isAuthorized = false;

    if (path.startsWith('pfp/')) {
      const filename = path.split('/')[1].split('.')[0];
      if (filename.startsWith('group_')) {
        // Group icons: any authenticated user can upload (groupId is not a UID)
        isAuthorized = true;
      } else {
        isAuthorized = (filename === decodedUid);
      }
    } else if (path.startsWith('chat_files/')) {
      const pathUid = path.split('/')[1];
      isAuthorized = (pathUid === decodedUid);
    } else if (path.startsWith('post_files/')) {
      const pathUid = path.split('/')[1];
      isAuthorized = (pathUid === decodedUid);
    } else if (path.startsWith('voice_files/')) {
      const pathUid = path.split('/')[1];
      isAuthorized = (pathUid === decodedUid);
    }

    if (!isAuthorized) {
      return new Response('Forbidden - Path UID does not match Token UID', { status: 403, headers: corsHeaders });
    }

    // 3. Size limits for uploads
    if (request.method === 'PUT') {
      const contentLength = request.headers.get('content-length');
      if (contentLength && parseInt(contentLength) > 20 * 1024 * 1024) { // 20 MB
        return new Response('Payload Too Large', { status: 413, headers: corsHeaders });
      }

      await env.MY_BUCKET.put(path, request.body);
      return new Response('Uploaded Successfully', { status: 200, headers: corsHeaders });
    }

    // 4. Delete operation
    if (request.method === 'DELETE') {
      if (path.endsWith('/')) {
        // Bulk delete: remove all objects under this prefix
        let cursor;
        do {
          const listed = await env.MY_BUCKET.list({ prefix: path, cursor });
          for (const obj of listed.objects) {
            await env.MY_BUCKET.delete(obj.key);
          }
          cursor = listed.truncated ? listed.cursor : undefined;
        } while (cursor);
      } else {
        await env.MY_BUCKET.delete(path);
      }
      return new Response('Deleted Successfully', { status: 200, headers: corsHeaders });
    }

    return new Response('Bad Request', { status: 400, headers: corsHeaders });
  }
};

// --- Helper Functions ---
async function verifyFirebaseJWT(token, projectId) {
  // Extract unverified kid
  const [headerB64] = token.split('.');
  const header = JSON.parse(atob(headerB64.replace(/-/g, '+').replace(/_/g, '/')));
  const kid = header.kid;

  // Fetch Google's public JWKS
  const resp = await fetch('https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com');
  const keys = await resp.json();
  const jwk = keys.keys.find(k => k.kid === kid);

  if (!jwk) throw new Error('Unknown kid');

  // Import key directly using the JWK format
  const cryptoKey = await crypto.subtle.importKey(
    'jwk',
    jwk,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    true,
    ['verify']
  );

  // Verify Signature
  const [h, p, s] = token.split('.');
  const signature = str2ab(atob(s.replace(/-/g, '+').replace(/_/g, '/')));
  const data = new TextEncoder().encode(`${h}.${p}`);

  const isValid = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', cryptoKey, signature, data);
  if (!isValid) throw new Error('Signature invalid');

  // Check claims
  const payload = JSON.parse(atob(p.replace(/-/g, '+').replace(/_/g, '/')));
  const now = Math.floor(Date.now() / 1000);

  if (payload.exp < now) throw new Error('Token expired');
  if (payload.aud !== projectId) throw new Error(`Invalid audience. Expected: ${projectId}, got: ${payload.aud}`);
  if (payload.iss !== `https://securetoken.google.com/${projectId}`) throw new Error('Invalid issuer');

  return payload.user_id;
}

function str2ab(str) {
  const buf = new ArrayBuffer(str.length);
  const bufView = new Uint8Array(buf);
  for (let i = 0; i < str.length; i++) {
    bufView[i] = str.charCodeAt(i);
  }
  return buf;
}
