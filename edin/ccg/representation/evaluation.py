from .predarg import PredArgAssigner, DepLink


def _safe_divide(x: float, y: float):
    if x == 0.0 and y == 0.0:
        return 1.0
    elif x != 0.0 and y == 0.0:
        return 0.0
    else:
        return x/y


def f_score(p: float, r: float):
    if p == 0.0 and r == 0.0:
        return 0.0
    else:
        return 2*p*r/(p+r)


def prf_score_from_stats(overlap: int, gold_count: int, pred_count: int):
    p = _safe_divide(overlap, pred_count)*100
    r = _safe_divide(overlap, gold_count)*100
    f = f_score(p, r)
    return p, r, f


def overlap(xs, ys):
    ys = set(ys)
    return sum([x in ys for x in xs])


def _to_directed_labelled_dep(d : DepLink):
    return d.head_cat, d.dep_slot, d.head_pos, d.dep_pos


def _to_undirected_unlabelled_dep(d : DepLink):
    return min(d.head_pos, d.dep_pos), max(d.head_pos, d.dep_pos)


def sufficient_stats(gold_tree, pred_tree, language):
    stats = dict()

    predarg_assigner = PredArgAssigner(language, include_conj_term=False)

    gold_deps = predarg_assigner.all_deps(gold_tree)
    pred_deps = predarg_assigner.all_deps(pred_tree)

    gold_labelled = [_to_directed_labelled_dep(d) for d in gold_deps]
    pred_labelled = [_to_directed_labelled_dep(d) for d in pred_deps]
    stats['labelled_overlap'] = overlap(gold_labelled, pred_labelled)
    stats['labelled_gold_count'] = len(gold_labelled)
    stats['labelled_pred_count'] = len(pred_labelled)

    gold_unlabelled = [_to_undirected_unlabelled_dep(d) for d in gold_deps]
    pred_unlabelled = [_to_undirected_unlabelled_dep(d) for d in pred_deps]
    stats['unlabelled_overlap'] = overlap(gold_unlabelled, pred_unlabelled)
    stats['unlabelled_gold_count'] = len(gold_unlabelled)
    stats['unlabelled_pred_count'] = len(pred_unlabelled)

    return stats


def combine_stats(stats):
    labelled_overlap = sum(x['labelled_overlap'] for x in stats)
    labelled_gold_count = sum(x['labelled_gold_count'] for x in stats)
    labelled_pred_count = sum(x['labelled_pred_count'] for x in stats)
    unlabelled_overlap = sum(x['unlabelled_overlap'] for x in stats)
    unlabelled_gold_count = sum(x['unlabelled_gold_count'] for x in stats)
    unlabelled_pred_count = sum(x['unlabelled_pred_count'] for x in stats)
    lab_prf = prf_score_from_stats(labelled_overlap,
                                   labelled_gold_count,
                                   labelled_pred_count)
    ulab_prf = prf_score_from_stats(unlabelled_overlap,
                                    unlabelled_gold_count,
                                    unlabelled_pred_count)

    all_scores = {'labeled_P': lab_prf[0],
                  'labeled_R': lab_prf[1],
                  'labeled_F': lab_prf[2],
                  'unlabeled_P': ulab_prf[0],
                  'unlabeled_R': ulab_prf[1],
                  'unlabeled_F': ulab_prf[2]}
    return all_scores
