// Cloudflare Worker для відправки Telegram сповіщень
// URL: https://watchdog-notifier.YOUR_SUBDOMAIN.workers.dev

addEventListener('fetch', event => {
  event.respondWith(handleRequest(event.request))
})

async function handleRequest(request) {
  // CORS headers для доступу з Debian сервера
  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
  }

  // Обробка preflight запиту
  if (request.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders })
  }

  // Дозволяємо тільки POST
  if (request.method !== 'POST') {
    return new Response('Method not allowed', {
      status: 405,
      headers: corsHeaders
    })
  }

  try {
    // Отримуємо дані від Watchdog
    const data = await request.json()

    // Валідація даних
    if (!data.message || !data.chat_id || !data.token) {
      return new Response(JSON.stringify({
        success: false,
        error: 'Missing required fields: message, chat_id, token'
      }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    // Формуємо повідомлення для Telegram
    const telegramMessage = `🚨 *PROXY WATCHDOG ALERT*\n\n${data.message}`

    // Отримуємо список чатів
    let chatIds = []
    if (Array.isArray(data.chat_id)) {
      chatIds = data.chat_id
    } else if (typeof data.chat_id === 'string') {
      chatIds = data.chat_id.split(',').map(id => id.trim())
    } else {
      chatIds = [data.chat_id.toString()]
    }

    const telegramUrl = `https://api.telegram.org/bot${data.token}/sendMessage`
    const results = []

    // Відправляємо кожному отримувачу
    for (const chat_id of chatIds) {
      if (!chat_id) continue

      const response = await fetch(telegramUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
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
        message: `Notification sent successfully to ${chatIds.length} recipients`,
        results: results
      }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    } else {
      return new Response(JSON.stringify({
        success: false,
        error: 'Some or all Telegram notifications failed',
        results: results
      }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

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