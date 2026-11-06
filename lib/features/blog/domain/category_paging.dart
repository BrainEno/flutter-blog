/// How many articles one category page holds.
///
/// The API caps `limit` at 100 and defaults this route to 20; a page that comes
/// back shorter than this is the end of the list, which is the only "has more"
/// signal the endpoint offers.
const int kCategoryPageSize = 20;

/// How many categories the catalog asks for in one request.
///
/// The API caps `limit` at 100 and offers no total, so the catalog is one page:
/// a full page means "there may be more", not "this is everything".
const int kCategoryListLimit = 100;
