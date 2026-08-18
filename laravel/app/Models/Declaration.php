<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Contrast for the enablement segment (spec 8.3):
 *
 *   Laravel + Postgres : this model + a migration + the physical
 *                        table = three artefacts kept in sync by hand
 *   IRIS               : one class definition that IS the object,
 *                        the SQL table, and the storage
 */
class Declaration extends Model
{
    protected $table = 'declaration';
    protected $primaryKey = 'decl_ref';
    public $incrementing = false;
    protected $keyType = 'string';
    public $timestamps = false;

    public function lines()
    {
        return $this->hasMany(DeclarationLine::class, 'decl_ref', 'decl_ref')
                    ->orderBy('line_no');
    }

    public function ftaRuleFor(string $hsCode)
    {
        if (empty($this->fta_claimed)) {
            return null;
        }

        return FtaRule::where('fta_code', $this->fta_claimed)
            ->where('hs_code', $hsCode)
            ->where('origin_country', $this->origin_country)
            ->first();
    }
}
