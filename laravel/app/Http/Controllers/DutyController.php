<?php

namespace App\Http\Controllers;

use App\Models\Declaration;
use Illuminate\Http\Request;

/**
 * Duty calculation, PHP/Laravel implementation.
 *
 * The redevelopment candidate: the same fiscal calculation the COBOL
 * core performs, reimplemented in the tender's target language
 * (SMK TS3-02).
 *
 * Arithmetic note - this divergence is intentional and must not be
 * corrected. This implementation uses native PHP floats and rounds once
 * at the total; the COBOL rounds each line to 2dp before accumulating.
 * On multi-line declarations the two differ by around a cent.
 *
 * bcmath or integer minor units would be the correct implementation.
 * The divergence is retained because finding it is what the SMK 5.7
 * fiscal-equivalence gate exists to do before cutover.
 */
class DutyController extends Controller
{
    public function calculate(Request $request)
    {
        // Failure injection for the resilience demo: in SHADOW the
        // router must still return the COBOL answer, unaffected.
        //
        // Read from a file rather than the environment so it can be
        // changed without restarting the container, which would mask
        // the behaviour under test.
        $failMode = 'off';
        if (is_readable('/opt/app/storage/failmode')) {
            $failMode = trim(file_get_contents('/opt/app/storage/failmode'));
        }
        if ($failMode === 'on') {
            return response()->json(['error' => 'service unavailable'], 500);
        }
        if ($failMode === 'hang') {
            sleep(30);
        }

        $ref = trim($request->input('declarationRef', ''));

        if ($ref === '') {
            return response()->json(['error' => 'declarationRef required'], 400);
        }

        $declaration = Declaration::with(['lines.tariff'])
            ->where('decl_ref', $ref)
            ->first();

        if (!$declaration) {
            return response()->json(['error' => 'declaration not found'], 404);
        }

        $totalDuty    = 0.0;   // accumulated at FULL float precision
        $totalSst     = 0.0;
        $totalValue   = 0.0;
        $prefApplied  = false;
        $lineDetails  = [];

        foreach ($declaration->lines as $line) {
            $tariff = $line->tariff;

            $rate = (float) $tariff->duty_rate;

            $fta = $declaration->ftaRuleFor($tariff->hs_code);

            // Boundary condition: strictly greater-than, where the
            // COBOL uses >=. A declaration exactly on the threshold is
            // treated differently. Intentional.
            if ($fta && (float) $declaration->local_pct > (float) $fta->min_local_pct) {
                $rate = (float) $fta->pref_rate;
                $prefApplied = true;
            }

            $customsValue = (float) $line->customs_value;

            $lineDuty = $customsValue * $rate;
            $lineSst  = ($customsValue + $lineDuty) * (float) $tariff->sst_rate;

            $totalDuty  += $lineDuty;    // no per-line rounding
            $totalSst   += $lineSst;
            $totalValue += $customsValue;

            $lineDetails[] = [
                'lineNo'        => (int) $line->line_no,
                'hsCode'        => $tariff->hs_code,
                'hsDescription' => $tariff->description,   // full, untruncated
                'rateApplied'   => round($rate, 4),
                'customsValue'  => round($customsValue, 2),
                'lineDuty'      => round($lineDuty, 2),
                'lineSst'       => round($lineSst, 2),
            ];
        }

        // Rounded once, at the end.
        $totalDuty = round($totalDuty, 2);
        $totalSst  = round($totalSst, 2);

        return response()->json([
            'status'            => 'OK',
            'declarationRef'    => $declaration->decl_ref,
            'lineCount'         => count($lineDetails),
            'totalCustomsValue' => round($totalValue, 2),
            'totalDutyAmount'   => $totalDuty,
            'totalSstAmount'    => $totalSst,
            'totalPayable'      => round($totalDuty + $totalSst, 2),
            'preferenceApplied' => $prefApplied,
            'calculatedAt'      => now()->toIso8601String(),   // ISO-8601 + TZ
            'lines'             => $lineDetails,
            'backend'           => 'PHP',
        ]);
    }

    public function health()
    {
        return response()->json(['status' => 'UP']);
    }
}
