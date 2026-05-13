// Falling Code — Feedback Worker
//
// Receives POST /submit from the Mac app and creates a GitHub Issue on
// the matrix-screensaver repo on the user's behalf.
//
// Why this exists: GitHub's API requires authentication via a Personal
// Access Token, and we can't ship that token inside the Mac app binary
// (anyone who decompiled the app would steal it). This Worker holds the
// token as a Cloudflare secret and proxies submissions safely.
//
// Secrets configured via `wrangler secret put`:
//   GITHUB_TOKEN — fine-grained PAT with Issues: Read+Write on the repo
//   APP_SECRET   — random string; the app sends this in `X-App-Secret`
//                  so random internet POSTs get a 401
//
// Free-tier limits (Cloudflare Workers):
//   - 100,000 requests/day. We'll use <100/year.
//
// To deploy from this directory:
//   wrangler deploy

const GITHUB_REPO = "WadeSellers/matrix-screensaver";

const MAX_TITLE_LEN = 200;
const MAX_DESCRIPTION_LEN = 5000;
const MAX_EMAIL_LEN = 254;

export default {
    async fetch(request, env) {
        // CORS preflight (probably not needed for a native app, but
        // costs nothing to handle correctly).
        if (request.method === "OPTIONS") {
            return new Response(null, {
                headers: corsHeaders(),
            });
        }

        if (request.method !== "POST") {
            return jsonError(405, "Method not allowed");
        }

        const url = new URL(request.url);
        if (url.pathname !== "/submit") {
            return jsonError(404, "Not found");
        }

        // Shared-secret check. The app sends this header with a value
        // baked into the binary. Reverse-engineerable but raises the
        // bar against random POSTs from the internet.
        if (request.headers.get("X-App-Secret") !== env.APP_SECRET) {
            return jsonError(401, "Unauthorized");
        }

        let payload;
        try {
            payload = await request.json();
        } catch {
            return jsonError(400, "Invalid JSON");
        }

        const validation = validatePayload(payload);
        if (validation.error) {
            return jsonError(400, validation.error);
        }

        const { kind, title, description, email, deviceInfo } = payload;
        const issueTitle = `[${kind === "bug" ? "Bug" : "Feature"}] ${title}`;
        const issueBody = buildIssueBody({ description, email, deviceInfo });
        const labels = [
            "feedback",
            kind === "bug" ? "bug" : "enhancement",
        ];

        const ghResponse = await fetch(
            `https://api.github.com/repos/${GITHUB_REPO}/issues`,
            {
                method: "POST",
                headers: {
                    Authorization: `token ${env.GITHUB_TOKEN}`,
                    Accept: "application/vnd.github+json",
                    "X-GitHub-Api-Version": "2022-11-28",
                    "User-Agent": "FallingCode-Feedback-Worker",
                    "Content-Type": "application/json",
                },
                body: JSON.stringify({
                    title: issueTitle,
                    body: issueBody,
                    labels,
                }),
            }
        );

        if (!ghResponse.ok) {
            const text = await ghResponse.text();
            console.error(
                `GitHub API failure ${ghResponse.status}: ${text}`
            );
            return jsonError(502, "Could not create issue. Please try again.");
        }

        const issue = await ghResponse.json();
        return new Response(
            JSON.stringify({
                issueNumber: issue.number,
                url: issue.html_url,
            }),
            {
                status: 200,
                headers: {
                    "Content-Type": "application/json",
                    ...corsHeaders(),
                },
            }
        );
    },
};

// MARK: - Helpers

function validatePayload(p) {
    if (!p || typeof p !== "object") {
        return { error: "Missing payload" };
    }
    if (!["bug", "feature"].includes(p.kind)) {
        return { error: "Field 'kind' must be 'bug' or 'feature'" };
    }
    if (typeof p.title !== "string" || p.title.trim().length === 0) {
        return { error: "Field 'title' is required" };
    }
    if (p.title.length > MAX_TITLE_LEN) {
        return { error: `Field 'title' exceeds ${MAX_TITLE_LEN} characters` };
    }
    if (typeof p.description !== "string" || p.description.trim().length === 0) {
        return { error: "Field 'description' is required" };
    }
    if (p.description.length > MAX_DESCRIPTION_LEN) {
        return {
            error: `Field 'description' exceeds ${MAX_DESCRIPTION_LEN} characters`,
        };
    }
    if (
        p.email !== undefined &&
        p.email !== null &&
        p.email !== "" &&
        (typeof p.email !== "string" || p.email.length > MAX_EMAIL_LEN)
    ) {
        return { error: "Field 'email' invalid" };
    }
    return {};
}

function buildIssueBody({ description, email, deviceInfo }) {
    const lines = [];
    lines.push(description.trim());
    lines.push("");
    lines.push("---");
    lines.push("");

    if (deviceInfo && typeof deviceInfo === "object") {
        lines.push("<details>");
        lines.push("<summary>Device info</summary>");
        lines.push("");
        if (deviceInfo.appVersion) {
            const build = deviceInfo.appBuild ? ` (build ${deviceInfo.appBuild})` : "";
            lines.push(`- App: Falling Code ${deviceInfo.appVersion}${build}`);
        }
        if (deviceInfo.osVersion) {
            lines.push(`- macOS: ${deviceInfo.osVersion}`);
        }
        if (deviceInfo.locale) {
            lines.push(`- Locale: ${deviceInfo.locale}`);
        }
        lines.push("");
        lines.push("</details>");
    }

    // Email goes in an HTML comment so it's there for the maintainer
    // (visible in the issue's edit/raw view) but doesn't render in the
    // public-facing issue page.
    if (email && email.trim().length > 0) {
        lines.push("");
        lines.push(`<!-- Contact email: ${email.trim()} -->`);
    }

    return lines.join("\n");
}

function jsonError(status, message) {
    return new Response(JSON.stringify({ error: message }), {
        status,
        headers: {
            "Content-Type": "application/json",
            ...corsHeaders(),
        },
    });
}

function corsHeaders() {
    return {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, X-App-Secret",
    };
}
