// The project filter and how it combines with the search: which request each
// change costs, what the cache answers by itself, and the empty state.
//
// The filter is part of the list's query key, so a change of project is a
// different entry — fetched through the backend once, kept after, and shown
// again from the cache when the user comes back.
import { expect, test } from '@playwright/test'
import { createTask, requestCounter, sweepTestTasks, uniqueName } from './backend'
import { trackInputListeners, typeInto } from './flutter_input'
import { listSettled, open, pickProject, row, searchField } from './helpers'

test.beforeAll(async ({ request }) => sweepTestTasks(request))
test.afterAll(async ({ request }) => sweepTestTasks(request))
test.use({ viewport: { width: 1280, height: 1600 } })
test.beforeEach(({ page }) => trackInputListeners(page))

test('picking a project narrows the list through the backend, one request per pick', async ({ page, request }) => {
  const admin = await createTask(request, uniqueName('Admin job'), { project: 'Admin' })
  const website = await createTask(request, uniqueName('Website job'), { project: 'Website' })
  await open(page)
  await expect(row(page, admin.name)).toBeVisible()
  await expect(row(page, website.name)).toBeVisible()
  await listSettled(page)
  const requests = requestCounter(page)

  await pickProject(page, 'All projects', 'Admin')
  await expect(row(page, admin.name)).toBeVisible()
  await expect(row(page, website.name)).toBeHidden()
  expect(requests.listQueries()).toEqual([{ search: '', project: 'Admin' }])

  await pickProject(page, 'Admin', 'Website')
  await expect(row(page, website.name)).toBeVisible()
  await expect(row(page, admin.name)).toBeHidden()
  expect(requests.listQueries()).toEqual([
    { search: '', project: 'Admin' },
    { search: '', project: 'Website' },
  ])
})

test('a project and a search narrow together, in one request', async ({ page, request }) => {
  // Two tasks that share the word searched for and differ in project: the
  // search alone finds both, the project alone finds neither of them
  // exclusively, and only the two together leave one.
  const word = uniqueName('Shared')
  const admin = await createTask(request, `Admin ${word}`, { project: 'Admin' })
  const website = await createTask(request, `Website ${word}`, { project: 'Website' })
  await open(page)
  await expect(row(page, admin.name)).toBeVisible()
  await listSettled(page)
  const requests = requestCounter(page)

  await typeInto(page, searchField(page), word)
  // The seed's rows go once the search's answer is in; the two tasks stay.
  await expect(row(page, 'Write the release notes')).toBeHidden()
  await expect(row(page, admin.name)).toBeVisible()
  await expect(row(page, website.name)).toBeVisible()
  expect(requests.listQueries()).toEqual([{ search: word, project: 'all' }])

  await pickProject(page, 'All projects', 'Admin')
  await expect(row(page, website.name)).toBeHidden()
  await expect(row(page, admin.name)).toBeVisible()
  await expect(page.getByRole('button', { name: /^Delete / })).toHaveCount(1)
  // One request for the pair, carrying both, not a search and then a project.
  expect(requests.listQueries()).toEqual([
    { search: word, project: 'all' },
    { search: word, project: 'Admin' },
  ])
})

test('switching back to All projects shows the hidden rows again from cache, with no request', async ({
  page,
  request,
}) => {
  const admin = await createTask(request, uniqueName('Admin job'), { project: 'Admin' })
  const website = await createTask(request, uniqueName('Website job'), { project: 'Website' })
  await open(page)
  await expect(row(page, website.name)).toBeVisible()
  await pickProject(page, 'All projects', 'Admin')
  await expect(row(page, website.name)).toBeHidden()
  await expect(row(page, admin.name)).toBeVisible()
  await listSettled(page)
  const requests = requestCounter(page)

  // The unfiltered entry is cached and fresh (45 s), so the rows are back
  // from it: the list is settled, not fetching, in the frame they appear in.
  await pickProject(page, 'Admin', 'All projects')
  await expect(row(page, website.name)).toBeVisible()
  await expect(row(page, admin.name)).toBeVisible()
  await listSettled(page)
  expect(requests.lists()).toBe(0)
})

test('a project with nothing in it shows the empty state', async ({ page }) => {
  // Every project the dropdown offers has a task in the backend's seed, and
  // emptying one would take the seed away from every later test. So the
  // backend's answer for one project is an empty list, said in the browser.
  await page.route('**/api/tasks?*', (route) => {
    if (new URL(route.request().url()).searchParams.get('project') !== 'Errands') return route.fallback()
    return route.fulfill({
      headers: { 'access-control-allow-origin': '*' },
      json: { tasks: [], fetchedAt: new Date().toISOString() },
    })
  })
  await open(page)
  await expect(row(page, 'Write the release notes')).toBeVisible()

  await pickProject(page, 'All projects', 'Errands')
  await expect(page.getByText('No tasks found.')).toBeVisible()
  await expect(page.getByRole('button', { name: /^Delete / })).toHaveCount(0)

  await pickProject(page, 'Errands', 'All projects')
  await expect(row(page, 'Write the release notes')).toBeVisible()
  await expect(page.getByText('No tasks found.')).toBeHidden()
})
