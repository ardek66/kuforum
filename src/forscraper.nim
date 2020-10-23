import std / [
  asyncdispatch, httpclient, sequtils,
  json, htmlparser, times, options,
  strformat, strutils
]

import karax / [karaxdsl, vdom]

import types

type
  ForumThreadId = distinct int

const
  ThreadsUrl = "https://forum.nim-lang.org/threads.json"
  PostsUrl = "https://forum.nim-lang.org/posts.json"

proc getPostContent(p: Post): string =
  if p.history.len > 0:
    p.history[^1].content
  else:
    p.info.content

proc getLastThreads(start = 0, count = 30): Future[seq[Thread]] {.async.} =
  var client = newAsyncHttpClient()
  var resp = await client.get(fmt"{ThreadsUrl}?start={start}&count={count}")
  if resp.code != Http200:
    client.close()
    return

  let body = parseJson(await resp.body).to(ThreadList)
  client.close()
  
  result = body.threads

proc getThreadInfo(id: ForumThreadId): Future[PostList] {.async.} =
  var client = newAsyncHttpClient()
  var resp = await client.get(fmt"{PostsUrl}?id={int(id)}")
  if resp.code != Http200:
    client.close()
    return
  
  result = parseJson(await resp.body).to(PostList)
  client.close()

proc makeThreadEntry(thr: Thread): VNode =
  result = buildHtml():
    tr:
      td(class="thread-title"):
        a(href="/t/" & $int(thr.id)): text thr.topic
      td(class="thread-author"): text "placeholder" #$thr.author
      td(class="hide-sm views-text"): text $thr.views

proc makeThreadsList(p: int, tl: seq[Thread]): VNode =
  result = buildHtml():
      table(id="threads-list", class="table"):
        thead:
          tr:
            th: text "Topic"
            th: text "Author"
            th: text "Views"

        tbody:
          for thr in tl:
            makeThreadEntry(thr)

          tr(class = "load-more-separator"):
            td(colspan = "6"):
              a(href = "/p/" & $(p + 1)):
                text "Go to the next page"

proc makeMainPage(page: int, tl: seq[Thread]): string =
  let vnode = buildHtml():
    html:
      head:
        link(
          rel="stylesheet",
          href="https://forum.nim-lang.org/css/nimforum.css"
        )
        title: text "Test forum"
      body:
        section(class = "thread-list"):
          makeThreadsList(page, tl)

  result = $vnode

proc makePosts(pl: PostList): VNode =
  result = buildHtml():
    section(class = "container grid-xl"):
      tdiv(id = "thread-title", class = "title"):
        p(class = "title-text"): text pl.thread.topic

      tdiv(class = "posts"):
        for post in pl.posts:
          tdiv(id = $post.id, class = "post"):
            tdiv(class = "post-icon"):
              figure(class = "post-avatar"):
                img(src = post.author.avatarUrl, title = $post.author)

            tdiv(class = "post-main"):
              tdiv(class = "post-title"):
                tdiv(class = "post-username"):
                  text $post.author
              tdiv(class = "post-content"):
                verbatim(getPostContent(post))

proc makeThreadPage(pl: PostList): string =
  let vnode = buildHtml():
    html:
      head:
        link(
          rel="stylesheet",
          href="https://forum.nim-lang.org/css/nimforum.css"
        )
        title: text fmt"{pl.thread.topic} - Nim forum"
      body:
        makePosts(pl)
  result = $vnode

import jester

routes:
  get "/":
    let page = 1
    let thrs = await getLastThreads(start = (page - 1) * 30)
    resp makeMainPage(page, thrs)

  get "/p/@page":
    let page =
      try: parseInt(@"page")
      except ValueError: resp "Invalid page count"
    let thrs = await getLastThreads(start = (page - 1) * 30)
    resp makeMainPage(page, thrs)

  get "/t/@id":
    let id = try:
      ForumThreadId(parseInt(@"id"))
    except ValueError:
      resp "Invalid thread id"

    let thr = await getThreadInfo(id)
    resp makeThreadPage(thr)
