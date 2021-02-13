import std / [
  asyncdispatch, httpclient, sequtils,
  json, htmlparser, xmltree, times, options,
  strformat, strutils, cgi,
]

import types

type
  ForumThreadId = distinct int

const
  ThreadsUrl = "https://forum.nim-lang.org/threads.json"
  PostsUrl = "https://forum.nim-lang.org/posts.json"

proc getPostContent(p: Post): string =
  let content =
    if p.history.len > 0:
      p.history[^1].content
    else:
      p.info.content

  # God have mercy upon the following code
  
  let html = parseHtml(content)
  for elem in html:
    case elem.kind
    of xnElement:
      for i in 0..<elem.len:
        let child = elem[i]
        if child.kind == xnElement:
          var text = child.innerText
          case child.tag
          of "li": result.add "\n* " & text
          of "p": result.add '>' & text & '\n'
          of "pre":
            text.removeSuffix("Run")
            result.add "\n````\n" & text & "\n```\n"
          else: result.add text
        
        else: result.add child.text
      
    of xnText: result.add elem.text
    else: discard

  if not result.endsWith('\n'): result.add '\n' # Force newline

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

proc makeThreadsList(p: int, tl: seq[Thread]): string =
  let scriptAddr = &"gemini://{getServerName()}/{getScriptFilename()}?"
  result.add "# NimForum threads, page " & $p & '\n'
  
  for thr in tl:
    result.add &"=> {scriptAddr & $thr.id} {int(thr.id)} {thr.topic}\n"

  let nextPage = scriptAddr & 'p' & $(p+1)
  result.add "\n=>" & nextPage & " Go to the next page"


proc makePosts(pl: PostList): string =
     result.add "# " & pl.thread.topic & '\n'

     for post in pl.posts:
       result.add "### " & $post.author & '\n'
       result.add getPostContent(post) & '\n'

proc mainPage(page: int) {.async.} =
  let thrs = await getLastThreads((page - 1) * 30)
  stdout.write makeThreadsList(page, thrs)

proc threadPage(id: int) {.async.} =
  let post = await getThreadInfo(ForumThreadId(id))
  stdout.write makePosts(post)

let query = getQueryString()
if query.len > 1:
  if query[0] == 'p':
    waitFor mainPage(parseInt(query[1..^1]))
  else:
    waitFor threadPage(parseInt(query))
    
#[
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
]#

