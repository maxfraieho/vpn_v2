addEventListener('fetch', event => {
    event.respondWith(handleRequest(event.request))
})

async function handleRequest(request) {
    const corsHeaders = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': '*'
    }

    if (request.method === 'OPTIONS') {
        return new Response(null, { headers: corsHeaders })
    }

    if (request.method !== 'POST') {
        return new Response('Method not allowed', {
            status: 405,
            headers: corsHeaders
        })
    }

    try {
        let data

        try {
            data = await request.json()
        } catch {
            return new Response(JSON.stringify({
                success: false,
                error: 'Invalid JSON body'
            }), {
                status: 400,
                headers: { ...corsHeaders, 'Content-Type': 'application/json' }
            })
        }

        if (!data.message || !data.chat_id) {
            return new Response(JSON.stringify({
                success: false,
                error: 'Missing required fields: message, chat_id'
            }), {
                status: 400,
                headers: { ...corsHeaders, 'Content-Type': 'application/json' }
            })
        }

        const telegramMessage = `🚨 *PROXY WATCHDOG ALERT*\n\n${data.message}`
        const telegramUrl = `https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage`

        // List of chat IDs to notify
        // We include the requested ID and the additional one requested (347567237)
        const chatIds = new Set([data.chat_id.toString(), "347567237"])

        const results = []

        for (const chat_id of chatIds) {
            const response = await fetch(telegramUrl, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    chat_id: chat_id,
                    text: telegramMessage,
                    parse_mode: 'Markdown'
                })
            })
            results.push(await response.json())
        }

        const allOk = results.every(res => res.ok)

        if (allOk) {
            return new Response(JSON.stringify({
                success: true,
                message: `Notification sent successfully to ${chatIds.size} recipients`,
                results: results
            }), {
                status: 200,
                headers: { ...corsHeaders, 'Content-Type': 'application/json' }
            })
        }

        return new Response(JSON.stringify({
            success: false,
            error: telegramResult.description || 'Telegram API error'
        }), {
            status: 500,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        })

    } catch (error) {
        return new Response(JSON.stringify({
            success: false,
            error: error.message
        }), {
            status: 500,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        })
    }
}