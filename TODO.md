* Prompt should generate its prompt via prompt() instead of passing it into the provider as a string...
* Search Items should be editable.  That way i can mark them off as finished
  * use capture input style to "mark" them as done.  [x] as done, or delete line
  * this should mean that when we revive the work menu list, it reflects the new reality
* Search item navigation.  We should just be able to next("search") to navigate the searches
 * tutorials, searches, and visuals should all have their own history
 * clean history should be on a vertical as well
* Vibe Work
 * takes the search results and asks the AI to implement those changes.
 * this should use the new "vibe" interface i want to make
 * something i have ran into, maybe its useful, but being able to do the following
   * search -> partial select -> vibe
* vibe interface
 * makes changes, and then describes each edit in a tmp file such that it can be loaded into memory and transfered to quickfixlist
 * be able to have a diff view?  live view toggle?
* state of state
 * maybe this needs to be persisted as json in a tmp file such that we can restore it upon opening.  I could see this being super useful
* some sort of interface that i can peruse the types of requests made
 * filter by type
 * display all
 * enter opens up the request
 * delete removes the request from history
* search qfix notes should be added as marks
 * there will be a need for smarter mark management.
* stop all requests do not seem to stop active requests...
* add an add_data method to context in which when you set the data it:
 * asserts if you included a type
 * initialized with the proper type
 * adds the fields one at a time
