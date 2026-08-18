<?php

namespace App\Http\Controllers;

use App\Models\Manifest;
use Illuminate\Support\Facades\DB;

/**
 * Vessel manifest lookup, PHP/Laravel implementation.
 *
 * Three behaviours here disagree with the COBOL program. All three are
 * intentional and must not be corrected: classifying them is the
 * exercise.
 *
 *   1. consignmentCount reads the denormalised declared_consignments
 *      column; COBOL counts the actual records. They differ where that
 *      counter has drifted.
 *
 *   2. statusCode is expanded through the lookup table - RELEASED
 *      rather than the stored RL. A different value on the wire.
 *
 *   3. eta is serialised in UTC. COBOL carries no timezone and is read
 *      as Asia/Kuala_Lumpur. The same instant, rendered differently.
 *
 * Whether any of these fails the SMK 5.7 gate is a judgement for JKDM.
 */
class ManifestController extends Controller
{
    public function lookup(string $manifestRef)
    {
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

        $ref = trim($manifestRef);
        $manifest = Manifest::with('consignments')
            ->where('manifest_ref', $ref)
            ->first();

        if (!$manifest) {
            return response()->json(['error' => 'manifest not found'], 404);
        }

        // Expanded through the lookup rather than returned as stored.
        $statusName = DB::table('manifest_status')
            ->where('status_code', $manifest->status_code)
            ->value('status_name');

        $lines = [];
        $totalGross = 0.0;
        foreach ($manifest->consignments as $c) {
            $totalGross += (float) $c->gross_kg;
            $lines[] = [
                'lineNo'         => (int) $c->line_no,
                'consignmentRef' => $c->consignment_ref,
                'containerCount' => (int) $c->container_count,
                'grossKg'        => round((float) $c->gross_kg, 2),
                'description'    => $c->description,   // full, untruncated
            ];
        }

        return response()->json([
            'status'           => 'OK',
            'manifestRef'      => $manifest->manifest_ref,
            'vesselId'         => $manifest->vessel_id,
            'vesselName'       => $manifest->vessel_name,
            'voyageNumber'     => $manifest->voyage_no,
            'carrierTin'       => $manifest->carrier_tin,
            'portOfDischarge'  => $manifest->port_of_discharge,
            'eta'              => date('c', strtotime($manifest->eta)),
            'statusCode'       => $statusName,
            'consignmentCount' => (int) $manifest->declared_consignments,
            'totalGrossKg'     => round($totalGross, 2),
            'consignments'     => $lines,
            'backend'          => 'PHP',
        ]);
    }
}
