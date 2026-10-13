import { t } from '../../utils/trpc';
import { getGifCategoriesRoute } from './get-gif-categories';
import { getTrendingGifsRoute } from './get-trending-gifs';
import { searchGifsRoute } from './search-gifs';

export const gifsRouter = t.router({
  categories: getGifCategoriesRoute,
  trending: getTrendingGifsRoute,
  search: searchGifsRoute
});
