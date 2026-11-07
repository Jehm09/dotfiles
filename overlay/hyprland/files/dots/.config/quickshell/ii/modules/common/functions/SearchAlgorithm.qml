pragma Singleton
import Quickshell
import qs.modules.common

/**
 * Elige cómo se buscan apps y entradas del portapapeles según search.algorithm:
 * fuzzy (siglas: "vsc"), levenshtein (typos: "discrod") o hybrid (fuzzy y, si no encuentra nada, typos).
 */
Singleton {
    id: root
    readonly property string algorithm: Config.options?.search.algorithm ?? "fuzzy"
    readonly property real levenshteinThreshold: 0.2
    // El costo de Levenshtein crece ~cuadrático con el largo del texto buscado
    readonly property int levenshteinMaxQueryLength: 20
    readonly property int hybridMinQueryLength: 4

    // Una cuenta ("12*45", "=sqrt(2)") nunca coincide con un nombre: no vale la pena pasarle Levenshtein
    function looksLikeMath(query) {
        const mathPrefix = Config.options?.search.prefix.math ?? "=";
        return query.startsWith(mathPrefix) || /^\s*[\d(.]/.test(query) || /[+*\/^%=]/.test(query);
    }

    function levenshteinSearch(query, candidates, scoreOf) {
        const cappedQuery = query.toLowerCase().slice(0, root.levenshteinMaxQueryLength);
        return candidates.map(entry => ({
            entry: entry,
            score: scoreOf(entry, cappedQuery)
        })).filter(item => item.score > root.levenshteinThreshold)
            .sort((a, b) => b.score - a.score)
            .map(item => item.entry);
    }

    // fuzzySearch: () => entries; scoreOf: (entry, queryLowercase) => puntaje 0..1
    function search(query, fuzzySearch, candidates, scoreOf, algorithmOverride) {
        const algorithm = algorithmOverride ?? root.algorithm;
        if (algorithm === "levenshtein" && !looksLikeMath(query))
            return levenshteinSearch(query, candidates, scoreOf);

        const fuzzyResults = fuzzySearch();
        const wantsTypoMatches = algorithm === "hybrid"
            && fuzzyResults.length === 0
            && query.trim().length >= root.hybridMinQueryLength
            && !looksLikeMath(query);
        if (!wantsTypoMatches)
            return fuzzyResults;

        return levenshteinSearch(query, candidates, scoreOf);
    }
}
