import * as stylex from '@stylexjs/stylex';
import {
	border,
	family,
	figures,
	radius,
	text,
	tracking,
	weight,
} from '@canmi/kit/tokens/vocabulary.stylex';

/**
 * The console's recipes, on the kit's palette and vocabulary: color, type, border and radius here,
 * where a thing sits in the markup. See web's spec/architecture/css/layers.md.
 */
export const surfaces = stylex.create({
	card: {
		backgroundColor: 'color-mix(in oklch, var(--color-text) 3%, transparent)',
		borderWidth: border.hairlinePx,
		borderStyle: 'solid',
		borderColor: 'var(--color-border)',
		borderRadius: radius.xl,
	},
	/** A slot with nothing in it yet, said plainly rather than filled. */
	empty: {
		borderWidth: border.hairlinePx,
		borderStyle: 'dashed',
		borderColor: 'var(--color-border-strong)',
		borderRadius: radius.xl,
	},
	rowRule: {
		borderTopWidth: border.hairlinePx,
		borderTopStyle: 'solid',
		borderTopColor: 'var(--color-border)',
	},
	/** The same rule between the items of a list, and none above the first. */
	listRule: {
		borderTopWidth: border.hairlinePx,
		borderTopStyle: 'solid',
		borderTopColor: { default: 'var(--color-border)', ':first-child': 'transparent' },
	},
	well: {
		backgroundColor: 'color-mix(in oklch, var(--color-text) 5%, transparent)',
		borderRadius: radius.lg,
	},
	pill: {
		borderRadius: radius.full,
	},
	dot: {
		borderRadius: radius.full,
		backgroundColor: 'currentColor',
	},
});

export const type = stylex.create({
	title: {
		fontSize: '1.25rem', // unnamed
		fontWeight: weight.semibold,
		color: 'var(--color-text-strong)',
	},
	heading: {
		fontSize: text.px15,
		fontWeight: weight.semibold,
		color: 'var(--color-text-strong)',
	},
	name: {
		fontSize: text.px14,
		fontWeight: weight.medium,
		color: 'var(--color-text-strong)',
	},
	body: {
		fontSize: text.px13,
		color: 'var(--color-text)',
	},
	soft: {
		fontSize: text.px12,
		color: 'var(--color-text-soft)',
	},
	label: {
		fontSize: text.px11,
		fontWeight: weight.medium,
		letterSpacing: tracking.caps,
		textTransform: 'uppercase',
		color: 'var(--color-text-soft)',
	},
	figure: {
		fontSize: text.px13,
		fontVariantNumeric: figures.tabular,
		color: 'var(--color-text-strong)',
	},
	mono: {
		fontFamily: family.monoTheme,
		fontSize: text.px12,
	},
});

/** The one color a state is shown in, wherever it is shown. */
export const tone = stylex.create({
	good: { color: 'var(--color-green)' },
	busy: { color: 'var(--color-blue)' },
	warn: { color: 'var(--color-amber)' },
	bad: { color: 'var(--color-red)' },
	quiet: { color: 'var(--color-text-soft)' },
});

export type Tone = keyof typeof tone;

/** A state's word washed in its tone. */
export const wash = stylex.create({
	good: { backgroundColor: 'color-mix(in oklch, var(--color-green) 14%, transparent)' },
	busy: { backgroundColor: 'color-mix(in oklch, var(--color-blue) 14%, transparent)' },
	warn: { backgroundColor: 'color-mix(in oklch, var(--color-amber) 16%, transparent)' },
	bad: { backgroundColor: 'color-mix(in oklch, var(--color-red) 14%, transparent)' },
	quiet: { backgroundColor: 'color-mix(in oklch, var(--color-text) 6%, transparent)' },
});
