import { useSelector } from 'react-redux';
import { stickersSelector } from './selectors';

export const useStickers = () => useSelector(stickersSelector);
